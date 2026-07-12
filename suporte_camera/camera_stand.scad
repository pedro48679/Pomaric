/*
 * ============================================================
 * RPi Camera V3 Stand — v6: 3 pecas (base / braco / cabeca)
 * FICHEIRO UNICO — funciona na versao web do OpenSCAD
 * ============================================================
 * COMO USAR: muda a variavel 'part' na linha abaixo e renderiza.
 *
 *   part = "assembly" -> conjunto montado (so pre-visualizacao)
 *   part = "base"     -> PECA 1: base com encaixe (exportar STL)
 *   part = "arm"      -> PECA 2: braco/coluna (exportar STL)
 *   part = "head"     -> PECA 3: moldura da camara (exportar STL)
 *
 * As pecas de impressao ja saem na orientacao certa. Suportes:
 * nenhuns na base e cabeca; no braco, so debaixo dos 2 pinos.
 *
 * Hardware: 4x M2 auto-roscante 6-8mm (camara) + 1x M2 opcional
 * para travar o braco na base. Sem M3, sem porcas.
 *
 * Montagem: braco encaixa a pressao na caixa da base (M2 opcional
 * por tras a travar); cabeca faz clique por cima dos pinos.
 * Ajuste de angulo ~ -25 a +45, friccao por interferencia.
 * ============================================================
 */

part = "assembly";   // <<<< MUDA AQUI: "assembly" | "base" | "arm" | "head"
display_tilt = 12;   // angulo da cabeca na pre-visualizacao

// preview leve (48), export com cilindros lisos (96) — friccao
// suave na dobradica e nos pinos
$fn = (part == "assembly") ? 48 : 96;
eps = 0.1;

/* ---------- Interface da camara (padrao real, medido no STEP oficial) ---------- */
hole_dx = 21.0;      // espacamento horizontal dos furos
hole_dz = 12.5;      // espacamento vertical dos furos
hole_d  = 1.8;       // furo piloto p/ M2 auto-roscante
pat_dz  = 3.7;       // offset real do padrao de furos da V3 (nao e centrado!)

pcb_w = 25.5;        // PCB 25.0 + folga
pcb_h = 24.5;        // PCB 23.86 + folga

wall_t   = 3;
lip_t    = 3;
pocket_d = 2.5;

plate_w = pcb_w + 2*wall_t;
plate_h = pcb_h + 2*wall_t;
plate_t = pocket_d + lip_t;

window_w = 17.5;
window_h = 15;
slot_w   = 17.5;

/* ---------- Dobradica snap-fit ---------- */
pivot_z   = 40;      // altura do eixo
pivot_y   = 11;      // eixo recuado: o disco do no fica RENTE a face
                     // traseira da lamina -> o braco imprime deitado
                     // sobre essa face, plano, sem suportes no no
arm_len   = 12;      // costas da placa -> eixo
hinge_d   = 14;      // disco do no e das abas (14 da 1.2mm de margem
                     // ao rebordo p/ furares o teu furo de bloqueio)
knuckle_w = 18;      // largura do no central (abas ficam POR FORA
                     // do rasgo do cabo e da lamina — sem colisoes)
stub_d    = 5.0;     // pinos laterais impressos
stub_l    = 3.0;
cheek_t   = 3.0;     // espessura de cada aba
squeeze   = 0.15;    // interferencia por lado (friccao) — AFINA AQUI (+-0.05)
snap_w    = 4.2;     // largura do canal de encaixe (< stub_d p/ reter)

/* ---------- Base & pes ---------- */
base_w   = 48;
base_l   = 42;
base_t   = 3.5;
frame_w  = 6;
corner_r = 6;
inner_r  = 14;       // raio do recorte interior GRANDE: enche os
                     // cantos da moldura p/ os pes assentarem em
                     // material cheio (o meio continua oco)
foot_d       = 8;    // pes da frente
rear_foot_d  = 10;   // pes de tras maiores
foot_h   = 2;
mount_hole_d = 3.5;
cbore_d      = 6.0;
cbore_depth  = 2.0;

/* ---------- Braco (lamina) ---------- */
col_w = 14;
col_t = 6;
col_y    = pivot_y + hinge_d/2 - col_t;  // garante disco rente a face
                                         // traseira da lamina (impressao plana)
blade_cy = col_y + col_t/2;       // centro da lamina (p/ caixa da base)
col_top  = pivot_z - hinge_d/2 - 1;

/* ---------- Encaixe base <-> braco ---------- */
sock_clr     = 0.15;  // folga por lado do encaixe (press-fit FDM
                      // realista; se dancar, o M2 de travamento segura)
socket_depth = 10;    // profundidade de encaixe da lamina
shoe_wall    = 2.5;
shoe_floor   = 2;

socket_w = col_w + 2*sock_clr;
socket_t = col_t + 2*sock_clr;
shoe_w   = socket_w + 2*shoe_wall;
shoe_l   = socket_t + 2*shoe_wall;
shoe_z0  = foot_h + base_t;                    // topo da moldura da base
shoe_top = shoe_z0 + shoe_floor + socket_depth;
blade_z0 = shoe_z0 + shoe_floor;               // cota do fundo da lamina

cheek_gap = knuckle_w/2 - squeeze;   // face interior de cada aba

/* ============================================================
 * 2D helper
 * ============================================================ */
module rrect(w, l, r)
    offset(r = r) square([w - 2*r, l - 2*r], center = true);

/* ============================================================
 * PECA 1: Base + caixa de encaixe (shoe)
 * ============================================================ */
module base_solid() {
    for (sx = [-1, 1], sy = [-1, 1])
        translate([sx*(base_w/2 - corner_r), sy*(base_l/2 - corner_r), 0])
            cylinder(d = (sy > 0 ? rear_foot_d : foot_d),
                     h = foot_h + eps);

    translate([0, 0, foot_h])
        linear_extrude(base_t)
            difference() {
                rrect(base_w, base_l, corner_r);
                rrect(base_w - 2*frame_w, base_l - 2*frame_w, inner_r);
            }

    // enchimento local sob a caixa (a moldura oca nao chega la)
    translate([-shoe_w/2, blade_cy - shoe_l/2, foot_h])
        cube([shoe_w, base_l/2 - (blade_cy - shoe_l/2), base_t]);
}

module base_holes() {
    for (sx = [-1, 1], sy = [-1, 1])
        translate([sx*(base_w/2 - corner_r), sy*(base_l/2 - corner_r), -eps]) {
            cylinder(d = mount_hole_d, h = base_t + foot_h + 2*eps);
        }
}

module shoe() {
    difference() {
        translate([-shoe_w/2, blade_cy - shoe_l/2, shoe_z0 - eps])
            cube([shoe_w, shoe_l, shoe_top - shoe_z0 + eps]);

        // caixa onde a lamina do braco encaixa a pressao
        translate([-socket_w/2, blade_cy - socket_t/2, blade_z0])
            cube([socket_w, socket_t, socket_depth + 2*eps]);

        // furo p/ M2 opcional de travamento, entra por tras
        translate([0, base_l/2 + 1, blade_z0 + socket_depth/2 + 0.5])
            rotate([90, 0, 0])
                cylinder(d = hole_d, h = shoe_wall + 8);
    }
}

module base_part() {
    difference() { base_solid(); base_holes(); }
    shoe();
}

/* ============================================================
 * PECA 2: Braco — lamina + no da dobradica com pinos
 * (definido na posicao de montagem; o output de impressao
 *  translada para assentar no z=0)
 * ============================================================ */
module column_solid() {
    // lamina vertical (o fundo fica dentro da caixa da base)
    translate([-col_w/2, col_y, blade_z0])
        cube([col_w, col_t, col_top - blade_z0]);

    // no: cilindro largo fundido com o topo da lamina
    // (rente a face traseira da lamina — a peca deita-se plana)
    hull() {
        translate([-knuckle_w/2, pivot_y, pivot_z])
            rotate([0, 90, 0]) cylinder(d = hinge_d, h = knuckle_w);
        translate([-col_w/2, col_y, col_top - 2])
            cube([col_w, col_t, 2]);
    }

    // pinos laterais (o eixo impresso)
    for (sx = [-1, 1])
        translate([sx == 1 ? knuckle_w/2 : -knuckle_w/2 - stub_l, pivot_y, pivot_z])
            rotate([0, 90, 0]) cylinder(d = stub_d, h = stub_l);
}

module arm_part() {
    difference() {
        column_solid();
        // piloto (passante) p/ o M2 de travamento
        translate([0, col_y + col_t + 1, blade_z0 + socket_depth/2 + 0.5])
            rotate([90, 0, 0])
                cylinder(d = 1.6, h = col_t + 2);
    }
}

/* ============================================================
 * PECA 3: MOLDURA — solido + abas snap da dobradica
 * ============================================================ */
module head_solid() {
    translate([-plate_w/2, 0, -plate_h/2])
        cube([plate_w, plate_t, plate_h]);

    // bosses de reforco SO nos 2 furos de cima —
    // os de baixo enroscam diretamente na raiz das abas
    for (sx = [-1, 1])
        translate([sx*hole_dx/2, plate_t - eps, pat_dz + hole_dz/2])
            rotate([-90, 0, 0])
                cylinder(d = 6, h = 3.5);

    // duas abas que abracam o no da coluna POR FORA
    // (raizes assentam em placa cheia, fora do rasgo do cabo;
    //  o FFC passa entre os dois bracos)
    for (sx = [-1, 1]) {
        xi = (sx == 1) ? cheek_gap : -cheek_gap - cheek_t;
        hull() {
            translate([xi, plate_t - eps, -hinge_d/2])
                cube([cheek_t, 1, hinge_d]);
            translate([xi, plate_t + arm_len, 0])
                rotate([0, 90, 0]) cylinder(d = hinge_d, h = cheek_t);
        }
    }

    // boss do parafuso de BLOQUEIO do angulo (aba direita):
    // aperta contra a face do no em qualquer angulo; quando
    // souberes o angulo definitivo, usa o furo da aba como guia
    // e fura 3-4mm para dentro do no (broca 1.6) -> tranca absoluta
    translate([cheek_gap + cheek_t - eps, plate_t + arm_len - 5, 0])
        rotate([0, 90, 0]) cylinder(d = 4.5, h = 2.5 + eps);
}

module head_cuts() {
    // 1. bolso da PCB
    translate([-pcb_w/2, -eps, -pcb_h/2])
        cube([pcb_w, pocket_d + eps, pcb_h]);

    // chanfro de entrada
    translate([-(pcb_w+1)/2, -eps, -(pcb_h+1)/2])
        cube([pcb_w+1, 0.6, pcb_h+1]);

    // 2. janela atras do sensor (deslocada p/ posicao real da lente)
    translate([-window_w/2, pocket_d - eps, -window_h/2 - 2.5])
        cube([window_w, lip_t + 2*eps, window_h]);

    // 3. saida do FFC em U (atravessa a parede toda)
    translate([-slot_w/2, -eps, -plate_h/2 - eps])
        cube([slot_w, plate_t + 2*eps, plate_h/2]);

    // strain relief do FFC
    translate([-slot_w/2, pocket_d, -plate_h/2])
        rotate([-45, 0, 0])
             cube([slot_w, 2, 2]);

    // 4. furos-piloto M2 (com offset real do padrao)
    for (sx = [-1, 1], sz = [-1, 1])
        translate([sx*hole_dx/2, -eps, pat_dz + sz*hole_dz/2])
            rotate([-90, 0, 0])
                cylinder(d = hole_d, h = plate_t + 5);

    // furo-piloto do parafuso de bloqueio (atravessa boss + aba)
    translate([cheek_gap - 1, plate_t + arm_len - 5, 0])
        rotate([0, 90, 0])
            cylinder(d = 1.6, h = cheek_t + 2.5 + 2);

    // 5. olhais das abas + canal de encaixe (abre para cima:
    //    o peso da camara empurra os pinos p/ o fundo do olhal)
    for (sx = [-1, 1]) {
        xi = (sx == 1) ? cheek_gap : -cheek_gap - cheek_t;
        translate([xi - eps, plate_t + arm_len, 0])
            rotate([0, 90, 0])
                cylinder(d = stub_d + 0.2, h = cheek_t + 2*eps);
        translate([xi - eps, plate_t + arm_len - snap_w/2, 0])
            cube([cheek_t + 2*eps, snap_w, hinge_d/2 + 1]);
    }
}

module head_part() {
    difference() { head_solid(); head_cuts(); }
}

// coloca a cabeca no eixo da dobradica, rodada 'tilt' graus
module at_hinge(tilt = 12) {
    translate([0, pivot_y, pivot_z])
        rotate([-tilt, 0, 0])
            translate([0, -(plate_t + arm_len), 0])
                children();
}

/* ============================================================
 * OUTPUT — controlado pela variavel 'part' no topo
 * ============================================================ */
if (part == "assembly") {
    base_part();
    arm_part();
    at_hinge(display_tilt) head_part();
} else if (part == "base") {
    base_part();                                    // ja orientada
} else if (part == "arm") {
    // DEITADO sobre a face traseira: layers correm ao longo do
    // braco (forte a flexao) e o furo do parafuso fica vertical
    // (roscas agarram varias layers). Suporte SO sob os 2 pinos.
    translate([0, -blade_z0, col_y + col_t])
        rotate([-90, 0, 0])
            arm_part();
} else if (part == "head") {
    rotate([90, 0, 0]) head_part();                 // lente contra a cama
}
