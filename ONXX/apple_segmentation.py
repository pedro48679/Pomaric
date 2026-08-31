#!/usr/bin/env python3
"""Apple segmentation and 224x224 framing for the Raspberry Pi pipeline.

Replaces the HSV-blob + RANSAC-circle detector. That detector modelled the
silhouette as a circle, which cannot represent a real apple outline, and picked
its blob by circularity, which on this dataset locks onto a lesion or a specular
highlight more often than onto the fruit: it recovered the apple on 38% of
benchmark frames, against 95% here.

Method
------
1. Locate. A Hough circle vote gives a centre and a rough radius; a corner-seeded
   colour model is the fallback. Corners rather than a border band, because a
   round fruit filling the frame leaves the band full of fruit while the corners
   stay background.
2. Outline. Ground-truth silhouettes are 97.3% star-convex about their centroid,
   so the outline is one radius per angle, r(theta). Dynamic programming finds
   the globally optimal closed path through a polar edge-cost image under a
   slope constraint. It cannot leak, fragment or collapse, and unlike a circle it
   follows the true contour.
3. Refine. The contour is re-solved at full resolution inside a narrow band, then
   rasterised from continuous radii.
4. Frame. A square crop on the mask bounding-box centre, side 1.025x the longer
   bbox side, resized to 224 -- the convention measured from the ground truth.

Benchmarked against 113 (raw, ground-truth) pairs recovered by content matching;
see benchmark_report.md. Held-out split: mask IoU 0.826, Dice 0.882,
precision 0.894, recall 0.913, boundary F 0.390, 16.6 ms/frame mean
(20.4 ms p95) single-threaded on a 2.1 GHz x86 core.
"""
import cv2
import numpy as np

# ---------------------------------------------------------------- parameters
WORK = 160          # working resolution, long side (192 and 256 were no better)
NA = 90             # angular samples (the star-convex ceiling is reached here)
STEP = 4            # max radius change between neighbouring angles, in samples
SMOOTH = 0.45       # quadratic slope penalty
OUTWARD = 0.05      # bias towards the outermost strong edge
MARGIN = 1.2        # search radius, as a multiple of the far-corner distance
RCAP_MULT = 1.8     # search radius cap, as a multiple of the located radius
BAND_HALF = 8       # full-resolution refinement band, in pixels
RADIUS_GAIN = 1.02  # systematic tightness correction (see below)
SIDE_FACTOR = 1.025  # crop side / mask bbox side, measured from the ground truth
OUT_SIZE = 224

_HOUGH_SIDE = 128   # Hough only has to place a centre; its cost grows with area
_BINS_SHIFT = 4     # 16 x 16 x 16 Lab histogram
_NB = 256 >> _BINS_SHIFT


# ------------------------------------------------------------ colour model
def _smooth3(hist):
    """Separable [1 2 1] blur of a 3-D histogram, by whole-plane shifts."""
    h = hist.reshape(_NB, _NB, _NB)
    for ax in range(3):
        lo, hi = np.roll(h, 1, ax), np.roll(h, -1, ax)
        idx = [slice(None)] * 3
        idx[ax] = 0; lo[tuple(idx)] = 0
        idx[ax] = -1; hi[tuple(idx)] = 0
        h = 2.0 * h + lo + hi
    return h.reshape(-1)


def _lab_index(lab):
    q = lab >> _BINS_SHIFT
    return (q[..., 0].astype(np.int32) * _NB + q[..., 1]) * _NB + q[..., 2]


def _colour_centre(lab):
    """Centre of the region that matches a central seed better than the corners."""
    h, w = lab.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot(xx - (w - 1) / 2.0, yy - (h - 1) / 2.0) / (min(h, w) / 2.0)
    fg, bg = r < 0.35, r > 1.0
    idx = _lab_index(lab)
    hf = _smooth3(np.bincount(idx[fg].ravel(), minlength=_NB ** 3).astype(np.float32))
    hb = _smooth3(np.bincount(idx[bg].ravel(), minlength=_NB ** 3).astype(np.float32))
    pf, pb = hf / max(hf.sum(), 1.0), hb / max(hb.sum(), 1.0)
    m = (np.log((pf[idx] + 1e-4) / (pb[idx] + 1e-4)) > 0).astype(np.uint8)
    ker = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    m = cv2.morphologyEx(cv2.morphologyEx(m, cv2.MORPH_OPEN, ker), cv2.MORPH_CLOSE, ker)
    n, lbl, stats, cent = cv2.connectedComponentsWithStats(m, 8)
    if n <= 1:
        return None
    cy0, cx0 = (h - 1) / 2.0, (w - 1) / 2.0
    best = max(range(1, n), key=lambda i: stats[i, cv2.CC_STAT_AREA] * np.exp(
        -2.0 * np.hypot(cent[i][0] - cx0, cent[i][1] - cy0) / max(h, w)))
    area = stats[best, cv2.CC_STAT_AREA]
    if area < 0.005 * h * w:
        return None
    return float(cent[best][0]), float(cent[best][1]), float(np.sqrt(area / np.pi))


def _hough_centre(gray):
    h, w = gray.shape[:2]
    k = _HOUGH_SIDE / max(h, w)
    if k < 1.0:
        gray = cv2.resize(gray, (max(16, round(w * k)), max(16, round(h * k))),
                          interpolation=cv2.INTER_AREA)
    else:
        k = 1.0
    gh, gw = gray.shape[:2]
    c = cv2.HoughCircles(gray, cv2.HOUGH_GRADIENT, dp=2, minDist=min(gh, gw),
                         param1=100, param2=30,
                         minRadius=int(0.12 * min(gh, gw)),
                         maxRadius=int(0.75 * min(gh, gw)))
    if c is None:
        return None
    x, y, r = c[0][0]
    return float(x) / k, float(y) / k, float(r) / k


def locate(blur_rgb, lab):
    """Centre and rough radius. Hough first: on the benchmark its centre error is
    0.032 of frame width (median) against 0.066 for the colour model, because it
    assumes nothing about where the fruit sits."""
    h, w = lab.shape[:2]
    return (_hough_centre(cv2.cvtColor(blur_rgb, cv2.COLOR_RGB2GRAY))
            or _colour_centre(lab)
            or ((w - 1) / 2.0, (h - 1) / 2.0, 0.3 * min(h, w)))


# --------------------------------------------------------- polar contour
def _step_edge(polar_img, k):
    """|mean over [r, r+k) - mean over [r-k, r)| summed over channels. Window
    averaging suppresses the skin speckle a plain derivative fires on."""
    f = np.cumsum(np.pad(polar_img.astype(np.float32), ((0, 0), (k, k), (0, 0)), 'edge'), axis=1)
    return np.abs((f[:, 2 * k:, :] - f[:, k:-k, :]) - (f[:, k:-k, :] - f[:, :-2 * k, :])).sum(2) / k


def _dp(cost, step, smooth):
    """Minimum-cost radius per angle under a slope constraint, closed over the
    angular wrap by running two laps and reading back the second.

    The per-angle update is a min-convolution with a small quadratic kernel,
    evaluated as one strided add plus one argmin.
    """
    na, nr = cost.shape
    win = 2 * step + 1
    pen = (smooth * (np.arange(win, dtype=np.float32) - step) ** 2).astype(np.float32)
    acc = np.empty((2 * na, nr), np.float32)
    back = np.empty((2 * na, nr), np.int8)
    acc[0] = cost[0]
    padded = np.full(nr + 2 * step, np.float32(1e9), np.float32)
    view = np.lib.stride_tricks.sliding_window_view(padded, win)
    buf = np.empty((nr, win), np.float32)
    arg = np.empty(nr, np.int64)
    cols = np.arange(nr)
    for t in range(1, 2 * na):
        padded[step:step + nr] = acc[t - 1]
        np.add(view, pen, out=buf)
        np.argmin(buf, axis=1, out=arg)
        acc[t] = buf[cols, arg] + cost[t % na]
        back[t] = arg - step
    r = np.empty(2 * na, np.int32)
    r[-1] = int(np.argmin(acc[-1]))
    for t in range(2 * na - 1, 0, -1):
        r[t - 1] = min(nr - 1, max(0, r[t] + int(back[t, r[t]])))
    return r[na:]


def _geometry(shape, cx, cy, na, margin):
    h, w = shape[:2]
    R = margin * float(max(np.hypot(cx, cy), np.hypot(w - cx, cy),
                           np.hypot(cx, h - cy), np.hypot(w - cx, h - cy)))
    nr = max(48, int(round(R)))
    ang = (np.arange(na) + 0.5) * 2 * np.pi / na
    ca, sa = np.cos(ang), np.sin(ang)
    with np.errstate(divide='ignore', invalid='ignore'):
        tx = np.where(ca > 0, (w - 1 - cx) / ca, np.where(ca < 0, -cx / ca, np.inf))
        ty = np.where(sa > 0, (h - 1 - cy) / sa, np.where(sa < 0, -cy / sa, np.inf))
    rmax_i = np.clip((np.minimum(np.abs(tx), np.abs(ty)) / R * nr).astype(np.int32), 4, nr - 1)
    return R, nr, ca, sa, rmax_i


def _polygon(cx, cy, rad, ca, sa, shape):
    pts = np.stack([cx + rad * ca, cy + rad * sa], 1).astype(np.int32)
    m = np.zeros(shape[:2], np.uint8)
    cv2.fillPoly(m, [pts], 1)            # fillPoly clips to the frame
    return m > 0


def _contour(rgb, cx, cy, na=None, outward=None, smooth=None, step=None,
             margin=None, rcap=None):
    """Optimal star-convex outline around (cx, cy).

    The search deliberately extends past the frame: when the fruit is clipped by
    the border the contour continues outside, where there is no evidence and so
    no cost, and the polygon is clipped when filled. Forbidding those radii
    instead forces the path to track the rectangular frame -- which no smoothness
    prior can express -- and the contour collapses inwards.
    """
    na = NA if na is None else na
    outward = OUTWARD if outward is None else outward
    smooth = SMOOTH if smooth is None else smooth
    step = STEP if step is None else step
    margin = MARGIN if margin is None else margin
    R, nr, ca, sa, rmax_i = _geometry(rgb.shape, cx, cy, na, margin)
    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB)
    # WARP_FILL_OUTLIERS is not optional. The search deliberately extends past
    # the frame, and without this flag OpenCV leaves those samples uninitialised:
    # cv2.warpPolar then returns *different results for identical input* between
    # calls, which propagated all the way to a ~15 px swing in the contour radius
    # and was the real source of the run-to-run noise.
    pol = cv2.warpPolar(lab, (nr, na), (cx, cy), R,
                        cv2.WARP_POLAR_LINEAR | cv2.WARP_FILL_OUTLIERS)
    rr = np.arange(nr, dtype=np.float32)
    inside = rr[None, :] <= rmax_i[:, None]

    edge = _step_edge(pol, max(2, nr // 60)) * inside
    # normalise on a high percentile, not the max: one very strong unrelated edge
    # (a window frame, a tile joint) otherwise scales the fruit's own edge down
    # until the outward bias outvotes it and the contour balloons.
    edge = np.clip(edge / max(float(np.percentile(edge, 99.5)), 1e-6), 0.0, 1.0)
    cost = -edge - outward * (np.minimum(rr[None, :], rmax_i[:, None]) / nr)
    # Charging the out-of-frame region explicitly was tried (0.0 to 0.6) and
    # changes IoU by 0.0003, so it is not worth a parameter.

    if rcap is not None:
        cap = min(nr - 1, max(int(0.25 * nr), int(rcap / R * nr)))
        cost[:, cap + 1:] = 1e3
    cost[:, :max(3, nr // 14)] = 1e3      # the contour cannot collapse to a point

    idx = _dp(cost, step, smooth)
    rad = idx.astype(np.float32) / nr * R
    return _polygon(cx, cy, rad, ca, sa, rgb.shape), rad, ca, sa


def _refine_band(rgb_full, cx, cy, rad, ca, sa, half=None, step=4,
                 smooth=None, outward=None):
    """Re-solve the contour at full resolution inside a +/- `half` pixel band.

    The coarse pass runs on a downscaled image, so its boundary is quantised to
    several full-resolution pixels -- most of the remaining boundary error.
    """
    half = BAND_HALF if half is None else half
    smooth = SMOOTH if smooth is None else smooth
    outward = OUTWARD if outward is None else outward
    H, W = rgb_full.shape[:2]
    off = np.arange(-half, half + 1, dtype=np.float32)
    rg = rad[:, None] + off[None, :]
    xs = (cx + rg * ca[:, None]).astype(np.float32)
    ys = (cy + rg * sa[:, None]).astype(np.float32)
    valid = (xs >= 0) & (xs <= W - 1) & (ys >= 0) & (ys <= H - 1) & (rg > 1)
    # Sample from RGB and convert only the band. Converting the whole frame
    # first cost 15 ms of a 50 ms budget on a 2304x1296 capture, to use a few
    # thousand of its three million pixels.
    band = cv2.cvtColor(cv2.remap(rgb_full, xs, ys, cv2.INTER_LINEAR,
                                  borderMode=cv2.BORDER_REPLICATE),
                        cv2.COLOR_RGB2LAB)
    edge = _step_edge(band, 2) * valid
    edge = np.clip(edge / max(float(np.percentile(edge, 99.5)), 1e-6), 0.0, 1.0)
    cost = -edge - outward * (np.cumsum(valid, axis=1) / max(1, off.size))
    return rad + off[_dp(cost.astype(np.float32), step, smooth)]


# --------------------------------------------------------------- public API
def _downscale(rgb, work):
    """Downscale to `work` on the long side, returning (small, scale).

    A single INTER_AREA call from 2304 px touches every source pixel (~9 ms).
    Striding first cuts the pixel count by the square of the stride; the result
    is still area-averaged, and the Gaussian blur that follows hides the rest.
    """
    H, W = rgb.shape[:2]
    s = work / max(H, W)
    k = max(1, int(1.0 / (s * 3.0)))          # keep >=3x for the area average
    if k > 1:
        rgb = rgb[::k, ::k]
    small = cv2.resize(rgb, (max(8, round(W * s)), max(8, round(H * s))),
                       interpolation=cv2.INTER_AREA)
    return small, s


USE_WINDOW = False      # zoom to the fruit before segmenting (see fruit_window)
REQUIRE_FRUIT = False   # reject frames with no usable fruit (see has_fruit)
MIN_FRUIT_CONTRAST = 30.0   # chroma of the fruit against its surroundings
MIN_EDGE_SHARPNESS = 3.0    # steepest L step across the outline, per pixel
MIN_FRUIT_AREA = 0.002      # fraction of the frame
MAX_FRUIT_AREA = 0.60       # above this the "fruit" is the background
WINDOW_WORK = 256       # coarse pass resolution for finding the fruit window
WINDOW_MULT = 2.6       # window side, as a multiple of the coarse fruit radius


def salient_blob(rgb, work=None):
    """Largest compact, chromatically distinct blob in the frame.

    Returns None when nothing stands out, otherwise its geometry in
    full-resolution coordinates plus the evidence used to decide whether it is
    fruit at all.
    """
    work = WINDOW_WORK if work is None else work
    small, s = _downscale(rgb, work)
    lab = cv2.cvtColor(cv2.GaussianBlur(small, (5, 5), 0), cv2.COLOR_RGB2LAB)
    ab = lab[..., 1:].astype(np.float32)
    med = np.median(ab.reshape(-1, 2), axis=0)
    sal = np.hypot(ab[..., 0] - med[0], ab[..., 1] - med[1])
    peak = float(np.percentile(sal, 99.5))
    if peak < 12.0:                 # nothing stands out: fruit fills the frame
        return None

    m = (sal > max(8.0, 0.45 * peak)).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    n, lbl, st, cent = cv2.connectedComponentsWithStats(m, 8)
    h, w = m.shape
    best, score = None, 0.0
    for i in range(1, n):
        a = st[i, cv2.CC_STAT_AREA]
        bw, bh = st[i, cv2.CC_STAT_WIDTH], st[i, cv2.CC_STAT_HEIGHT]
        if a < 0.0015 * h * w or bw < 4 or bh < 4:
            continue
        v = a * (a / float(bw * bh)) * (min(bw, bh) / float(max(bw, bh)))
        if v > score:
            score, best = v, i
    if best is None:
        return None

    blob = lbl == best
    ring = cv2.dilate(blob.astype(np.uint8), np.ones((15, 15), np.uint8)) > 0
    ring &= ~blob
    a = st[best, cv2.CC_STAT_AREA]
    bw, bh = st[best, cv2.CC_STAT_WIDTH], st[best, cv2.CC_STAT_HEIGHT]
    return {
        'scale': s,
        'cx': float(cent[best][0]) / s, 'cy': float(cent[best][1]) / s,
        'radius': float(np.sqrt(a / np.pi)) / s,
        'area': a / float(h * w),
        'fill': a / float(bw * bh),
        'aspect': min(bw, bh) / float(max(bw, bh)),
        'peak': peak,
        # how much more chromatic the blob is than the ring around it. This is
        # the signal that separates fruit from an empty belt: on the rig
        # captures it never drops below 33.8, and on frames with no fruit it
        # never exceeds 26.8.
        'contrast': float(sal[blob].mean() - sal[ring].mean()) if ring.any() else 0.0,
    }


def fruit_window(rgb, work=None, mult=None, blob=None):
    """Square window containing the fruit, or None to use the whole frame.

    Enabled by USE_WINDOW, which is a property of the camera geometry, not of the
    frame. At 30-50 cm the fruit covers 1.3-6.1% of the frame, against ~73% in
    the fomat/ benchmark, so at the working resolution its radius falls to ~11 px
    -- below the smallest circle the localiser searches for. Zooming restores the
    regime the rest of the pipeline was validated in.

    It is a setting rather than a per-frame decision on purpose. Both geometries
    produce the same bottom-up structure -- one dominant material covering the
    border, one salient blob inside it -- and only the semantics differ (the blob
    is the fruit in one case, a lesion on the fruit in the other). Automatic
    switching was tried on blob area and on a brightness prior; every setting
    either regressed the close-up benchmark from IoU 0.839 to 0.70-0.79 or missed
    a third of the rig captures. The rig's camera distance is fixed and known, so
    this belongs in configuration.
    """
    mult = WINDOW_MULT if mult is None else mult
    b = salient_blob(rgb, work) if blob is None else blob
    if b is None or b['area'] > 0.25:      # already large: no need to zoom
        return None
    H, W = rgb.shape[:2]
    side = max(64, min(int(round(2 * mult * b['radius'])), min(H, W)))
    left = max(0, min(W - side, int(round(b['cx'] - side / 2.0))))
    top = max(0, min(H - side, int(round(b['cy'] - side / 2.0))))
    return left, top, side, (b['cx'] - left, b['cy'] - top)


def apple_contour(rgb, work=None, na=None, band_half=None, radius_gain=None,
                  rcap_mult=None, window=None, seed=None, blob=None, **kw):
    """Locate and outline the apple.

    Returns (cx, cy, radii, cos, sin) in full-resolution coordinates.

    Every tunable defaults to None and is resolved from the module constant at
    call time, so setting e.g. apple_segmentation.RADIUS_GAIN from the caller
    actually takes effect. Binding them as default arguments freezes them at
    import and silently ignores any later configuration.
    """
    work = WORK if work is None else work
    na = NA if na is None else na
    radius_gain = RADIUS_GAIN if radius_gain is None else radius_gain
    rcap_mult = RCAP_MULT if rcap_mult is None else rcap_mult
    use_win = USE_WINDOW if window is None else window
    win = fruit_window(rgb, blob=blob) if use_win else None
    if win is not None:
        left, top, side, seed = win
        sub = rgb[top:top + side, left:left + side]
        c = apple_contour(sub, work=work, na=na, band_half=band_half,
                          radius_gain=radius_gain, rcap_mult=rcap_mult,
                          window=False, seed=seed, **kw)
        return c[0] + left, c[1] + top, c[2], c[3], c[4]

    H, W = rgb.shape[:2]
    small, s = _downscale(rgb, work)
    blur = cv2.GaussianBlur(small, (5, 5), 0)
    lab = cv2.cvtColor(blur, cv2.COLOR_RGB2LAB)
    h, w = lab.shape[:2]

    if seed is not None:
        # The window stage already localised the fruit deterministically. Reusing
        # its centre skips the Hough vote entirely: Hough breaks accumulator ties
        # nondeterministically, and on this geometry that was flipping whole
        # outcomes (IoU varied by 0.13 between runs on identical input).
        cx, cy = seed[0] * s, seed[1] * s
        r0 = 0.5 * min(h, w) / WINDOW_MULT
    else:
        cx, cy, r0 = locate(blur, lab)
    rcap = r0 * rcap_mult if rcap_mult else None
    m, rad, ca, sa = _contour(blur, cx, cy, na=na, rcap=rcap, **kw)

    # Re-solve once from the mask's own centroid. A colour-model region term was
    # tried here too (a Chan-Vese style alternation) and is clearly harmful: the
    # background model is fitted just outside a contour that is not yet correct,
    # so any under-coverage feeds back and the contour collapses (IoU 0.72 vs 0.83).
    if m.sum() >= 0.005 * h * w:
        ys, xs = np.nonzero(m)
        cx2, cy2 = float(xs.mean()), float(ys.mean())
        if abs(cx2 - cx) >= 0.5 or abs(cy2 - cy) >= 0.5:
            cx, cy = cx2, cy2
            m, rad, ca, sa = _contour(blur, cx, cy, na=na, rcap=rcap, **kw)

    cxf, cyf, radf = cx / s, cy / s, rad / s
    # The band has to be wider than the coarse pass's own quantisation, which is
    # one working pixel = 1/s full-resolution pixels. A fixed 8 px band is finer
    # than that on a 2304 px capture, so the refinement would be searching
    # inside its own error.
    if band_half is None:
        band_half = max(8, int(round(3.0 / s)))
    if band_half > 0:
        radf = _refine_band(rgb, cxf, cyf, radf, ca, sa, half=band_half)
    # The solved contour sits a few per cent inside the ground truth, whose soft
    # matte thresholds just outside the visible edge the cost locks onto. The
    # correction lifts boundary F-score at 2 px tolerance from 0.18 to ~0.39.
    return cxf, cyf, radf * radius_gain, ca, sa


def contour_points(contour, shape):
    """Contour vertices as int32 (N, 2), clipped to the frame."""
    cx, cy, rad, ca, sa = contour
    H, W = shape[:2]
    x = np.clip(cx + rad * ca, 0, W - 1)
    y = np.clip(cy + rad * sa, 0, H - 1)
    return np.stack([x, y], 1).astype(np.int32)


def apple_mask(rgb, **kw):
    """Full-resolution boolean mask.

    Only needed by callers that work in full-resolution coordinates; for the 224
    output use segment_to_224, which never materialises this.
    """
    c = apple_contour(rgb, **kw)
    m = np.zeros(rgb.shape[:2], np.uint8)
    cv2.fillPoly(m, [contour_points(c, rgb.shape)], 1)
    return m > 0


def crop_from_contour(rgb, contour, out=None, factor=None):
    """Square crop around the contour, rendered directly at `out` px as RGBA.

    The obvious implementation -- rasterise the mask at full resolution, copy a
    side x side x 4 canvas, then INTER_AREA it down -- cost 218 ms on a 1385 px
    capture with a 1112 px crop: the 4-channel area resize is not vectorised.
    Here the colour is resized from the source rectangle (3 channels) and the
    alpha is rasterised straight into the output frame, so nothing larger than
    `out` is ever allocated.
    """
    out = OUT_SIZE if out is None else out
    factor = SIDE_FACTOR if factor is None else factor
    pts = contour_points(contour, rgb.shape)
    if pts.size == 0:
        return None
    x0, y0 = pts.min(0); x1, y1 = pts.max(0)
    side = max(1, int(round(max(x1 - x0 + 1, y1 - y0 + 1) * factor)))
    left = int(round((x0 + x1) / 2.0 - side / 2.0))
    top = int(round((y0 + y1) / 2.0 - side / 2.0))
    k = out / float(side)

    canvas = np.zeros((out, out, 4), np.uint8)
    H, W = rgb.shape[:2]
    sx0, sy0 = max(0, left), max(0, top)
    sx1, sy1 = min(W, left + side), min(H, top + side)
    if sx1 <= sx0 or sy1 <= sy0:
        return None
    dx0, dy0 = int(round((sx0 - left) * k)), int(round((sy0 - top) * k))
    dx1, dy1 = min(out, int(round((sx1 - left) * k))), min(out, int(round((sy1 - top) * k)))
    if dx1 <= dx0 or dy1 <= dy0:
        return None
    interp = cv2.INTER_AREA if (sx1 - sx0) > (dx1 - dx0) else cv2.INTER_LINEAR
    canvas[dy0:dy1, dx0:dx1, :3] = cv2.resize(rgb[sy0:sy1, sx0:sx1],
                                              (dx1 - dx0, dy1 - dy0), interpolation=interp)
    alpha = np.zeros((out, out), np.uint8)
    cv2.fillPoly(alpha, [np.round((pts - [left, top]) * k).astype(np.int32)], 255)
    canvas[..., 3] = alpha
    canvas[..., :3][alpha == 0] = 0
    return canvas


def crop_and_resize(rgb, mask, out=None, factor=None):
    """Square crop centred on a mask's bbox, resized to `out`, as RGBA uint8.
    Kept for callers that already hold a mask; the contour path is faster."""
    out = OUT_SIZE if out is None else out
    factor = SIDE_FACTOR if factor is None else factor
    ys, xs = np.nonzero(mask)
    if xs.size == 0:
        return None
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    side = max(1, int(round(max(x1 - x0 + 1, y1 - y0 + 1) * factor)))
    left = int(round((x0 + x1) / 2.0 - side / 2.0))
    top = int(round((y0 + y1) / 2.0 - side / 2.0))
    k = out / float(side)
    canvas = np.zeros((out, out, 4), np.uint8)
    H, W = mask.shape
    sx0, sy0 = max(0, left), max(0, top)
    sx1, sy1 = min(W, left + side), min(H, top + side)
    if sx1 <= sx0 or sy1 <= sy0:
        return None
    dx0, dy0 = int(round((sx0 - left) * k)), int(round((sy0 - top) * k))
    dx1, dy1 = min(out, int(round((sx1 - left) * k))), min(out, int(round((sy1 - top) * k)))
    if dx1 <= dx0 or dy1 <= dy0:
        return None
    dsz = (dx1 - dx0, dy1 - dy0)
    interp = cv2.INTER_AREA if (sx1 - sx0) > dsz[0] else cv2.INTER_LINEAR
    canvas[dy0:dy1, dx0:dx1, :3] = cv2.resize(rgb[sy0:sy1, sx0:sx1], dsz, interpolation=interp)
    a = cv2.resize(mask[sy0:sy1, sx0:sx1].astype(np.uint8) * 255, dsz,
                   interpolation=cv2.INTER_AREA)
    canvas[dy0:dy1, dx0:dx1, 3] = np.where(a > 128, 255, 0)
    canvas[..., :3][canvas[..., 3] == 0] = 0
    return canvas


def edge_sharpness(rgb, contour, half=6):
    """Steepest L step across the outline, in L units per pixel (median over rays).

    Laplacian variance inside the fruit is the wrong measure: apple skin is
    smooth, so a perfectly focused apple on a smooth sheet scores 18 while
    unusable frames reach 95. What separates them is how fast the image changes
    *across* the silhouette.
    """
    cx, cy, rad, ca, sa = contour
    H, W = rgb.shape[:2]
    off = np.arange(-half, half + 1, dtype=np.float32)
    rg = rad[:, None] + off[None, :]
    xs = (cx + rg * ca[:, None]).astype(np.float32)
    ys = (cy + rg * sa[:, None]).astype(np.float32)
    ok = ((xs >= 0) & (xs <= W - 1) & (ys >= 0) & (ys <= H - 1)).all(axis=1)
    if ok.sum() < 8:
        return 0.0
    band = cv2.remap(rgb, xs, ys, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    L = cv2.cvtColor(band, cv2.COLOR_RGB2LAB)[..., 0].astype(np.float32)
    return float(np.median(np.abs(np.diff(L, axis=1)).max(axis=1)[ok]))


def has_fruit(rgb, contour=None, blob=None):
    """Is there a usable apple in this frame? Returns (bool, reason, evidence).

    Calibrated on 16 rig captures containing fruit and 30 rig frames that do not
    (including four with an apple so defocused it is unusable). The deciding
    signal is how much more chromatic the fruit is than its surroundings:

        with fruit     minimum 33.8
        without fruit  maximum 26.8

    so any threshold in 28-32 separates them with no error either way; 30 sits in
    the middle. Boundary sharpness was measured as an alternative and is weaker
    (ranges overlap: 4.5 against 13.0), so it is kept only as a backstop for a
    vividly coloured but badly defocused fruit, which this negative set does not
    contain. Both are configurable.

    Only meaningful when the fruit is a distinct object in the frame, i.e. the
    rig geometry. On the fomat/raw close-ups the fruit *is* the background and
    contrast falls to 4.5, so REQUIRE_FRUIT must stay off for that material.
    """
    b = salient_blob(rgb) if blob is None else blob
    if b is None:
        return False, 'sem regiao distinta (fundo uniforme)', {}
    ev = {k: v for k, v in b.items() if k != 'scale'}
    if b['area'] < MIN_FRUIT_AREA:
        return False, f"regiao demasiado pequena ({b['area']*100:.2f}% do frame)", ev
    if b['area'] > MAX_FRUIT_AREA:
        return False, f"regiao demasiado grande ({b['area']*100:.0f}% do frame)", ev
    if b['contrast'] < MIN_FRUIT_CONTRAST:
        return False, f"contraste cromatico baixo ({b['contrast']:.1f} < {MIN_FRUIT_CONTRAST})", ev
    if contour is not None:
        sh = edge_sharpness(rgb, contour)
        ev['sharpness'] = sh
        if sh < MIN_EDGE_SHARPNESS:
            return False, f"contorno desfocado (nitidez {sh:.1f} < {MIN_EDGE_SHARPNESS})", ev
    return True, 'ok', ev


def segment_to_224(rgb, out=None):
    """RGB uint8 array -> (full-resolution mask, RGBA uint8 out x out).

    Returns (None, None) when REQUIRE_FRUIT is on and the frame holds no usable
    apple, so the caller can drop the frame instead of sending background.
    """
    # One salient-blob pass feeds both the gate and the window; computing it
    # three times cost 12 ms of the frame budget.
    blob = salient_blob(rgb) if (REQUIRE_FRUIT or USE_WINDOW) else None
    if REQUIRE_FRUIT:
        ok, _reason, _ = has_fruit(rgb, blob=blob)
        if not ok:
            return None, None
    c = apple_contour(rgb, blob=blob)
    if REQUIRE_FRUIT and edge_sharpness(rgb, c) < MIN_EDGE_SHARPNESS:
        return None, None
    m = np.zeros(rgb.shape[:2], np.uint8)
    cv2.fillPoly(m, [contour_points(c, rgb.shape)], 1)
    return m > 0, crop_from_contour(rgb, c, out=out)
