/* MUX21I is an inverting 2:1 multiplexor */
module MUX21I ( A, B, s, Q );
    input A;
    input B;
    input s;
    output Q;

    assign Q = ~ ( s ? A : B ); /* mock-up for FPGA implementation */
endmodule

module SELECT_NOT_8 ( A, B, s, Q );
    input [7:0] A;
    input [7:0] B;
    input s;
    output [7:0] Q;
    MUX21I m7(A[7],B[7],s,Q[7]);
    MUX21I m6(A[6],B[6],s,Q[6]);
    MUX21I m5(A[5],B[5],s,Q[5]);
    MUX21I m4(A[4],B[4],s,Q[4]);
    MUX21I m3(A[3],B[3],s,Q[3]);
    MUX21I m2(A[2],B[2],s,Q[2]);
    MUX21I m1(A[1],B[1],s,Q[1]);
    MUX21I m0(A[0],B[0],s,Q[0]);
endmodule

/* multiply in GF(2^4)/GF(2^2), shared factors, basis [alpha^8, alpha^2] */
module GF_MULS_4 ( A, a, Al, Ah, aa, B, b, Bl, Bh, bb, Q );
    input [3:0] A;
    input [1:0] a;
    input Al;
    
    input Ah;
    input aa;
    
    
    input [3:0] B;
    input [1:0] b;
    input Bl;
    
    input Bh;
    input bb;
    
    
    output [3:0] Q;
    wire
    // [1:0] ph, pl, ps, p;
    [1:0] ph, pl, p;
    // wire
    // t;
    GF_MULS_2 himul(A[3:2], Ah, B[3:2], Bh, ph);
    GF_MULS_2 lomul(A[1:0], Al, B[1:0], Bl, pl);
    GF_MULS_SCL_2 summul( a, aa, b, bb, p);
    assign Q = { (ph ^ p), (pl ^ p) };
endmodule

 /* multiply in GF(2^2), shared factors, using normal basis [Omega^2,Omega] */
module GF_MULS_2 ( A, ab, B, cd, Q );
    input [1:0] A;
    input ab;
    input [1:0] B;
    input cd;
    output [1:0] Q;
    wire
    abcd, p, q;
    assign abcd = ~(ab & cd); /* note: ~& syntax for NAND won’t compile */
    assign p = (~(A[1] & B[1])) ^ abcd;
    assign q = (~(A[0] & B[0])) ^ abcd;
    assign Q = { p, q };
endmodule

  /* square in GF(2^2), using normal basis [Omega^2,Omega] */
 /* inverse is the same as square in GF(2^2), using any normal basis */
module GF_SQ_2 ( A, Q );
    input [1:0] A;
    output [1:0] Q;
    assign Q = { A[0], A[1] };
endmodule

 /* multiply & scale by N in GF(2^2), shared factors, basis [Omega^2,Omega] */
module GF_MULS_SCL_2 ( A, ab, B, cd, Q );
    input [1:0] A;
    input ab;
    input [1:0] B;
    input cd;
    output [1:0] Q;
    wire
    t, p, q;
    assign t = ~(A[0] & B[0]); /* note: ~& syntax for NAND won’t compile */
    assign p = (~(ab & cd)) ^ t;
    assign q = (~(A[1] & B[1])) ^ t;
    assign Q = { p, q };
endmodule

module GF_INV_4 ( A, Q );
    input [3:0] A;
    output [3:0] Q;
    wire
    [1:0] a, b, c, d, p, q;
    wire
    sa, sb, sd; /* for shared factors in multipliers */
    assign a = A[3:2];
    assign b = A[1:0];
    assign sa = a[1] ^ a[0];
    assign sb = b[1] ^ b[0];
    /* optimize this section as shown below
    GF_MULS_2 abmul(a, sa, b, sb, ab);
    GF_SQ_2 absq( (a ^ b), ab2);
    GF_SCLW2_2 absclN( ab2, ab2N);
    GF_SQ_2 dinv( (ab ^ ab2N), d);
    */
    assign c = { /* note: ~| syntax for NOR won’t compile */
    ~(a[1] | b[1]) ^ (~(sa & sb)) ,
    ~(sa | sb) ^ (~(a[0] & b[0])) };
    GF_SQ_2 dinv( c, d);
    /* end of optimization */
    assign sd = d[1] ^ d[0];
    GF_MULS_2 pmul(d, sd, b, sb, p);
    GF_MULS_2 qmul(d, sd, a, sa, q);
    assign Q = { p, q };
endmodule

/* inverse in GF(2^8)/GF(2^4), using normal basis [d^16, d] */
 module GF_INV_8 ( A, Q );
    input [7:0] A;
    output [7:0] Q;
    wire
    [3:0] a, b, c, d, p, q;
    wire
    // [1:0] sa, sb, sd, t; /* for shared factors in multipliers */
    [1:0] sa, sb, sd; /* for shared factors in multipliers */
    wire al, ah, aa, bl, bh, bb, dl, dh, dd; /* for shared factors */
    wire c1, c2, c3; /* for temp var */

    assign a = A[7:4];
    assign b = A[3:0];
    assign sa = a[3:2] ^ a[1:0];
    assign sb = b[3:2] ^ b[1:0];
    assign al = a[1] ^ a[0];
    assign ah = a[3] ^ a[2];
    assign aa = sa[1] ^ sa[0];
    assign bl = b[1] ^ b[0];
    assign bh = b[3] ^ b[2];
    assign bb = sb[1] ^ sb[0];
    /* optimize this section as shown below
    GF_MULS_4 abmul(a, sa, al, ah, aa, b, sb, bl, bh, bb, ab);
    GF_SQ_SCL_4 absq( (a ^ b), ab2);
    GF_INV_4 dinv( (ab ^ ab2), d);
    */
    assign c1 = ~(ah & bh);
    assign c2 = ~(sa[0] & sb[0]);
    assign c3 = ~(aa & bb);
    assign c = { /* note: ~| syntax for NOR won’t compile */
    (~(sa[0] | sb[0]) ^ (~(a[3] & b[3]))) ^ c1 ^ c3 ,
    (~(sa[1] | sb[1]) ^ (~(a[2] & b[2]))) ^ c1 ^ c2 ,
    (~(al | bl) ^ (~(a[1] & b[1]))) ^ c2 ^ c3 ,
    (~(a[0] | b[0]) ^ (~(al & bl))) ^ (~(sa[1] & sb[1])) ^ c2 };
    GF_INV_4 dinv( c, d);
    /* end of optimization */
    assign sd = d[3:2] ^ d[1:0];
    assign dl = d[1] ^ d[0];
    assign dh = d[3] ^ d[2];
    assign dd = sd[1] ^ sd[0];
    GF_MULS_4 pmul(d, sd, dl, dh, dd, b, sb, bl, bh, bb, p);
    GF_MULS_4 qmul(d, sd, dl, dh, dd, a, sa, al, ah, aa, q);
    assign Q = { p, q };
endmodule

module sbox ( byte_in, byte_out );
    input [7:0] byte_in;
    output [7:0] byte_out;
    wire [7:0] B, C, D, Z; // X, Y,
    wire R1, R2, R3, R4, R5, R6, R7, R8, R9;
    wire T1, T2, T3, T4, T5, T6, T7, T8, T9;//, T10;

 /* change basis from GF(2^8) to GF(2^8)/GF(2^4)/GF(2^2) */
 /* combine with bit inverse matrix multiply of Sbox */
    assign R1 = byte_in[7] ^ byte_in[5] ;
    assign R2 = byte_in[7] ~^ byte_in[4] ;
    assign R3 = byte_in[6] ^ byte_in[0] ;
    assign R4 = byte_in[5] ~^ R3 ;
    assign R5 = byte_in[4] ^ R4 ;
    assign R6 = byte_in[3] ^ byte_in[0] ;
    assign R7 = byte_in[2] ^ R1 ;
    assign R8 = byte_in[1] ^ R3 ;
    assign R9 = byte_in[3] ^ R8 ;
    assign B[7] = R7 ~^ R8 ;
    assign B[6] = R5 ;
    assign B[5] = byte_in[1] ^ R4 ;
    assign B[4] = R1 ~^ R3 ;
    assign B[3] = byte_in[1] ^ R2 ^ R6 ;
    assign B[2] = ~ byte_in[0] ;
    assign B[1] = R4 ;
    assign B[0] = byte_in[2] ~^ R9 ;
    // assign Y[7] = R2 ;
    // assign Y[6] = byte_in[4] ^ R8 ;
    // assign Y[5] = byte_in[6] ^ byte_in[4] ;
    // assign Y[4] = R9 ;
    // assign Y[3] = byte_in[6] ~^ R2 ;
    // assign Y[2] = R7 ;
    // assign Y[1] = byte_in[4] ^ R6 ;
    // assign Y[0] = byte_in[1] ^ R5 ;
    // SELECT_NOT_8 sel_in( B, Y, 1'b1, Z );
    assign Z = ~ B;
    GF_INV_8 inv( Z, C );
    /* change basis back from GF(2^8)/GF(2^4)/GF(2^2) to GF(2^8) */
    assign T1 = C[7] ^ C[3] ;
    assign T2 = C[6] ^ C[4] ;
    assign T3 = C[6] ^ C[0] ;
    assign T4 = C[5] ~^ C[3] ;
    assign T5 = C[5] ~^ T1 ;
    assign T6 = C[5] ~^ C[1] ;
    assign T7 = C[4] ~^ T6 ;
    assign T8 = C[2] ^ T4 ;
    assign T9 = C[1] ^ T2 ;
    // assign T10 = T3 ^ T5 ;
    assign D[7] = T4 ;
    assign D[6] = T1 ;
    assign D[5] = T3 ;
    assign D[4] = T5 ;
    assign D[3] = T2 ^ T5 ;
    assign D[2] = T3 ^ T8 ;
    assign D[1] = T7 ;
    assign D[0] = T9 ;
    // assign X[7] = C[4] ~^ C[1] ;
    // assign X[6] = C[1] ^ T10 ;
    // assign X[5] = C[2] ^ T10 ;
    // assign X[4] = C[6] ~^ C[1] ;
    // assign X[3] = T8 ^ T9 ;
    // assign X[2] = C[7] ~^ T7 ;
    // assign X[1] = T6 ;
    // assign X[0] = ~ C[2] ;
    // SELECT_NOT_8 sel_out( D, X, 1'b1, byte_out );
    assign byte_out = ~ D;
 endmodule