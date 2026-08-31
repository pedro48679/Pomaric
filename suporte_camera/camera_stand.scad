/*
 * ============================================================
 * RPi Camera V3 Stand — v7: Braço Elegante e Mais Alto
 * ============================================================
 * COMO USAR: muda a variavel 'part' na linha abaixo e renderiza.
 *
 *   part = "assembly" -> conjunto montado (so pre-visualizacao)
 *   part = "base"     -> PECA 1: base com encaixe (exportar STL)
 *   part = "arm"      -> PECA 2: braco/coluna (exportar STL)
 *   part = "head"     -> PECA 3: moldura da camara (exportar STL)
 * ============================================================
 */

part = "assembly";   // <<<< MUDA AQUI: "assembly" | "base" | "arm" | "head"
display_tilt = 12;   // angulo da cabeca na pre-visualizacao

$fn = 48;
eps = 0.1;

/* ---------- Interface da camara (padrao real) ---------- */
hole_dx = 21.0;
hole_dz = 12.5;
hole_d  = 1.8;
pat_dz  = 3.7;

pcb_w = 26;
pcb_h = 25;

wall_t   = 3;
lip_t    = 3;
pocket_d = 5;

plate_w = pcb_w + 2*wall_t;
plate_h = pcb_h + 2*wall_t;
plate_t = pocket_d + lip_t;

window_w = 17.5;
window_h = 15;
slot_w   = 17.5;

/* ---------- Dobradica snap-fit ---------- */
pivot_z   = 105;      // <--- AUMENTADO: Braço mais alto (era 40)
pivot_y   = 26.5;      
arm_len   = 12;      
hinge_d   = 14;      
knuckle_w = 18;      
stub_d    = 5.0;     
stub_l    = 3.0;
cheek_t   = 3.0;     
squeeze   = 0.12;    
snap_w    = 4.2;     

/* ---------- Base & pes ---------- */
base_w   = 85;       // Mais larga para não tombar para os lados
base_l   = 75;      // Muito mais comprida para contrabalançar a luz
base_t   = 8;
frame_w  = 10;
corner_r = 6;
inner_r  = 14;       
foot_d       = 8;    
rear_foot_d  = 10;   
foot_h   = 2;
mount_hole_d = 3.5;
cbore_d      = 6.0;
cbore_depth  = 2.0;

/* ---------- Braco (lamina) ---------- */
col_w = 16;          // <--- REDUZIDO: Mais estreito em X (era 14)
col_t = 8;           // <--- REDUZIDO: Mais fino em Y (era 6)

// NOVA MATEMÁTICA: Mantém as costas do braço sempre alinhadas 
// com as costas da dobradiça para poder imprimir deitado perfeitamente plano.
col_y    = pivot_y + hinge_d/2 - col_t;  
blade_cy = col_y + col_t/2;       
col_top  = pivot_z - hinge_d/2 - 1;

/* ---------- Encaixe base <-> braco ---------- */
sock_clr     = 0.25;  
socket_depth = 10;    
shoe_wall    = 2.5;
shoe_floor   = 2;

socket_w = col_w + 2*sock_clr;
socket_t = col_t + 2*sock_clr;
shoe_w   = socket_w + 2*shoe_wall;
shoe_l   = socket_t + 2*shoe_wall;
shoe_z0  = foot_h + base_t;                    
shoe_top = shoe_z0 + shoe_floor + socket_depth;
blade_z0 = shoe_z0 + shoe_floor;               

cheek_gap = knuckle_w/2 - squeeze;   

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

    translate([-shoe_w/2, blade_cy - shoe_l/2, foot_h])
        cube([shoe_w, base_l/2 - (blade_cy - shoe_l/2), base_t]);
}

module base_holes() {
    for (sx = [-1, 1], sy = [-1, 1])
        translate([sx*(base_w/2 - corner_r), sy*(base_l/2 - corner_r), -eps]) {
            cylinder(d = mount_hole_d, h = base_t + foot_h + 2*eps);
            // Rebaixo mantido comentado/apagado conforme discutimos
            // cylinder(d = cbore_d, h = cbore_depth + foot_h + eps);
        }
}

module shoe() {
    difference() {
        translate([-shoe_w/2, blade_cy - shoe_l/2, shoe_z0 - eps])
            cube([shoe_w, shoe_l, shoe_top - shoe_z0 + eps]);

        translate([-socket_w/2, blade_cy - socket_t/2, blade_z0])
            cube([socket_w, socket_t, socket_depth + 2*eps]);

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
 * ============================================================ */
module column_solid() {
    translate([-col_w/2, col_y, blade_z0])
        cube([col_w, col_t, col_top - blade_z0]);

    hull() {
        translate([-knuckle_w/2, pivot_y, pivot_z])
            rotate([0, 90, 0]) cylinder(d = hinge_d, h = knuckle_w);
        translate([-col_w/2, col_y, col_top - 2])
            cube([col_w, col_t, 2]);
    }

    for (sx = [-1, 1])
        translate([sx == 1 ? knuckle_w/2 : -knuckle_w/2 - stub_l, pivot_y, pivot_z])
            rotate([0, 90, 0]) cylinder(d = stub_d, h = stub_l);
}

module arm_part() {
    difference() {
        column_solid();
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

    for (sx = [-1, 1])
        translate([sx*hole_dx/2, plate_t - eps, pat_dz + hole_dz/2])
            rotate([-90, 0, 0])
                cylinder(d = 6, h = 3.5);

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
    translate([cheek_gap + cheek_t - eps, plate_t + arm_len - 5, 0])
        rotate([0, 90, 0]) cylinder(d = 4.5, h = 2.5 + eps);
}

module head_cuts() {
    translate([-pcb_w/2, -eps, -pcb_h/2])
        cube([pcb_w, pocket_d + eps, pcb_h]);

    translate([-(pcb_w+1)/2, -eps, -(pcb_h+1)/2])
        cube([pcb_w+1, 0.6, pcb_h+1]);

    translate([-window_w/2, pocket_d - eps, -window_h/2 - 2.5])
        cube([window_w, lip_t + 2*eps, window_h]);

    translate([-slot_w/2, -eps, -plate_h/2 - eps])
        cube([slot_w, plate_t + 2*eps, plate_h/2]);

    translate([-slot_w/2, pocket_d, -plate_h/2])
        rotate([-45, 0, 0])
             cube([slot_w, 2, 2]);

    for (sx = [-1, 1], sz = [-1, 1])
        translate([sx*hole_dx/2, -eps, pat_dz + sz*hole_dz/2])
            rotate([-90, 0, 0])
                cylinder(d = hole_d, h = plate_t + 5);

    for (sx = [-1, 1]) {
        xi = (sx == 1) ? cheek_gap : -cheek_gap - cheek_t;
        translate([xi - eps, plate_t + arm_len, 0])
            rotate([0, 90, 0])
                cylinder(d = stub_d + 0.2, h = cheek_t + 2*eps);
        translate([xi - eps, plate_t + arm_len - snap_w/2, 0])
            cube([cheek_t + 2*eps, snap_w, hinge_d/2 + 1]);
    }

    // furo-piloto do parafuso de bloqueio (atravessa boss + aba)
    translate([cheek_gap - 1, plate_t + arm_len - 5, 0])
        rotate([0, 90, 0])
            cylinder(d = 1.6, h = cheek_t + 2.5 + 2);
}

module head_part() {
    difference() { head_solid(); head_cuts(); }
}

module at_hinge(tilt = 12) {
    translate([0, pivot_y, pivot_z])
        rotate([-tilt, 0, 0])
            translate([0, -(plate_t + arm_len), 0])
                children();
}

/* ============================================================
 * OUTPUT
 * ============================================================ */
if (part == "assembly") {
    base_part();
    arm_part();
    at_hinge(display_tilt) head_part();
} else if (part == "base") {
    base_part();                                    
} else if (part == "arm") {
    translate([0, -(col_y + col_t), -blade_z0])
        rotate([-90, 0, 0])
            arm_part();
} else if (part == "head") {
    rotate([90, 0, 0]) head_part();                 
}