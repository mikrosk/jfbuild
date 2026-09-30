| "Build Engine & Tools" Copyright (c) 1993-1997 Ken Silverman
| Ken Silverman's official web site: "http://www.advsys.net/ken"
| See the included license file "BUILDLIC.TXT" for license info.
|
| This file has been modified from Ken Silverman's original release
| by Jonathon Fowler (jf@jonof.id.au)
|
| m68k (68020-68060 + FPU) translation of a.nasm. The x86 original patches
| its own immediates at run time; the 68060 instruction cache makes that
| impractical, so every patched immediate is a variable in .bss instead
| and the labels of the patch points are kept as variable names.
| Instructions the 68060 leaves unimplemented (64-bit mul/div, movep,
| cas2, chk2/cmp2 and the transcendental FPU operations) are not used.
|
| Register mapping is chosen per function and given in a comment at the
| top of each one. Pixel packing is mirrored for big-endian longword
| stores.

	.text

| Macros to help make cdecl calling easier to manage.
| All arguments are on the stack; after saving \saved registers with
| movem, argument \n is at 4+4*\saved+4*\n(sp).

	.macro	CDECLBEGIN regs
	movem.l	\regs,-(%sp)
	.endm

	.macro	CDECLEND regs
	movem.l	(%sp)+,\regs
	.endm

#define ARG(n,saved)	(4+4*(saved)+4*(n))(%sp)

	.macro	ALIGN
	.balignw 4,0x4e71
	.endm


	.globl	sethlinesizes
	.globl	setvlinebpl
	.globl	setpalookupaddress
	.globl	setuphlineasm4
	.globl	hlineasm4
	.globl	setupmvlineasm
	.globl	setuptvlineasm
	.globl	prevlineasm1
	.globl	vlineasm1
	.globl	mvlineasm1			| Masked vline
	.globl	fixtransluscence
	.globl	settransnormal
	.globl	settransreverse
	.globl	tvlineasm1			| Masked & transluscent vline
	.globl	vlineasm4
	.globl	setupvlineasm
	.globl	mvlineasm4
	.globl	setupspritevline
	.globl	spritevline
	.globl	msetupspritevline
	.globl	mspritevline
	.globl	tsetupspritevline
	.globl	tspritevline
	.globl	msethlineshift
	.globl	mhline
	.globl	mhlineskipmodify
	.globl	tsethlineshift
	.globl	thline
	.globl	thlineskipmodify
	.globl	setuptvlineasm2
	.globl	tvlineasm2
	.globl	setupslopevlin
	.globl	slopevlin
	.globl	setuprhlineasm4
	.globl	rhlineasm4
	.globl	setuprmhlineasm4
	.globl	rmhlineasm4
	.globl	setupqrhlineasm4
	.globl	qrhlineasm4			| 4 pixels in 9 cycles!  2.25 cycles/pixel
	.globl	setupdrawslab
	.globl	drawslab
	.globl	stretchhline
	.globl	mmxoverlay


	ALIGN
sethlinesizes:
| eax=logx, ebx=logy, ecx=bufplc
	move.l	%d2,-(%sp)
	move.l	ARG(0,1),%d0
	move.l	ARG(1,1),%d1
	move.l	ARG(2,1),%d2

	move.l	%d0,machxbits			| machxbits1/2/3: xbits
	neg.l	%d0
	and.l	#31,%d0
	move.l	%d0,hxsiz			| hxsiz1-4, machnegxbits1: 32-xbits

	move.l	%d1,hysiz			| hysiz1-4, hmach3a-d: ybits
	moveq	#32,%d0
	sub.l	%d1,%d0
	move.l	%d0,hnegysiz			| 32-ybits, for the shld emulation

	move.l	%d2,hoffs			| hoffs1-8: bufplc

	moveq	#-1,%d2				| mov edx, -1
	move.l	hxsiz,%d0			| mov cl, al (al = -logx)
	sub.l	%d1,%d0				| sub cl, bl
	and.l	#31,%d0
	lsr.l	%d0,%d2				| shr edx, cl
	move.l	%d2,hmach2			| hmach2a-d: (1<<(xbits+ybits))-1

	move.l	(%sp)+,%d2
	rts


	ALIGN
setvlinebpl:
	move.l	ARG(0,0),fixchain	| fixchain1a/1b/1m/1t/1s, mfixchain1s,
						| tfixchain1s, fixchain2a/2ma/2mb,
						| fixchaint2a-e: bytes per line
	rts


	ALIGN
setpalookupaddress:
	move.l	ARG(0,0),hpal		| pal1-8
	rts


	ALIGN
setuphlineasm4:
| eax=bxinc, ebx=byinc
	move.l	%d2,-(%sp)
	move.l	ARG(0,1),%d0
	move.l	ARG(1,1),%d1

	move.l	machxbits,%d2
	rol.l	%d2,%d0				| machxbits3: rol eax, xbits
	move.l	%d0,hmach4			| hmach4a-d
	move.b	%d0,%d1				| mov bl, al
	move.l	%d1,hmach1			| hmach1a-d

	move.l	(%sp)+,%d2
	rts

	| Per pixel step of the alignment prologue and the short line loop:
	| d4=bx, d3=by, d5=32-xbits, d7=ybits, d6=32-ybits, d2=paloffs,
	| a2=bufplc, a3=palookup. Pixel is left in the low byte of d1.
	.macro	HPIX
	move.l	%d4,%d0				| mov eax, esi
	lsr.l	%d5,%d0				| hxsiz: shr eax, 32-xbits
	lsl.l	%d7,%d0				| hysiz: shld eax, edx, ybits
	move.l	%d3,%d1
	lsr.l	%d6,%d1
	or.l	%d1,%d0
	move.b	(%a2,%d0.l),%d2			| hoffs: mov cl, byte [eax+bufplc]
	move.b	(%a3,%d2.l),%d1			| pal: mov bl, byte [ecx+palookup]
	sub.l	asm1,%d4			| sub esi, dword [asm1]
	sub.l	asm2,%d3			| sub edx, dword [asm2]
	.endm

	| Non-256-stuffed ceiling&floor method with NO SHLD!:
	| yinc&0xffffff00   lea eax, [edx+88888800h]           1     1/2
	| ybits...xbits     and edx, 88000088h                 1     1/2
	| ybits             rol edx, 6                         2     1/2
	| xinc<<xbits       add esi, 88888888h                 1     1/2
	| xinc>>(32-xbits)  adc al, 88h                        1     1/2
	| bufplc            mov cl, byte [edx+88888888h]   1     1/2
	| paloffs&255       mov bl, byte [ecx+88888888h]   1     1/2
	|
	| eax=cnt, ebx=skiploadincs, ecx=paloffs, edx=by, esi=bx, edi=p
	|
	| d0: temp (eax)          d4: bx, later bx<<xbits (esi)
	| d1: 4 pixels (ebx)      d5: 32-xbits, later hmach1 (yinc)
	| d2: paloffs+texel (ecx) d6: 32-ybits, later mask (hmach2)
	| d3: by, later by/xint   d7: ybits
	| a0: p (edi)             a3: palookup
	| a1: count (ebp)         a4: hmach4 (xinc)
	| a2: bufplc              a5: variable block
	ALIGN
hlineasm4:
	CDECLBEGIN	%d2-%d7/%a2-%a5
#define SAVED 10
	move.l	ARG(0,SAVED),%a1		| lea ebp, [eax+1]
	addq.l	#1,%a1
	move.l	ARG(2,SAVED),%d2
	move.l	ARG(3,SAVED),%d3
	move.l	ARG(4,SAVED),%d4
	move.l	ARG(5,SAVED),%a0

	lea	hlinevars,%a5
	move.l	hoffs-hlinevars(%a5),%a2
	move.l	hpal-hlinevars(%a5),%a3
	move.l	hxsiz-hlinevars(%a5),%d5
	move.l	hysiz-hlinevars(%a5),%d7
	move.l	hnegysiz-hlinevars(%a5),%d6

	cmp.l	#8,%a1				| cmp ebp, 8
	ble	shorthline

	move.l	%a0,%d0				| test edi, 1
	btst	#0,%d0
	bne.b	skipthe1byte

	HPIX					| hxsiz1, hysiz1, hoffs1, pal1
	move.b	%d1,(%a0)			| mov byte [edi], bl
	subq.l	#1,%a0				| dec edi
	subq.l	#1,%a1				| dec ebp

skipthe1byte:
	move.l	%a0,%d0				| test edi, 2
	btst	#1,%d0
	bne.b	skipthe2byte

	HPIX					| hxsiz2, hysiz2, hoffs2, pal2 (bh)
	move.b	%d1,(%a0)			| mov word [edi-1], bx: bh goes to edi
	HPIX					| hxsiz3, hysiz3, hoffs3, pal3 (bl)
	move.b	%d1,-1(%a0)			|                      bl goes to edi-1
	subq.l	#2,%a0				| sub edi, 2
	subq.l	#2,%a1				| sub ebp, 2

skipthe2byte:
	move.l	%d4,%d0				| mov eax, esi
	move.l	machxbits-hlinevars(%a5),%d1
	lsl.l	%d1,%d4				| machxbits1: shl esi, xbits
	lsr.l	%d5,%d0				| machnegxbits1: shr eax, 32-xbits
	move.b	%d0,%d3				| mov dl, al

	addq.l	#1,%a0				| inc edi

	tst.l	ARG(1,SAVED)			| add ebx, ebx / jc beginhline64
	bmi.b	1f

	move.l	asm1,%d0
	rol.l	%d1,%d0				| machxbits2: rol eax, xbits
	move.l	%d0,hmach4-hlinevars(%a5)	| hmach4a-d
	move.l	asm2,%d1
	move.b	%d0,%d1				| mov al, bl
	move.l	%d1,hmach1-hlinevars(%a5)	| hmach1a-d
1:
	move.l	hmach1-hlinevars(%a5),%d5
	move.l	hmach4-hlinevars(%a5),%a4
	move.l	hmach2-hlinevars(%a5),%d6
	bra.b	beginhline64
	ALIGN
prebeginhline64:
	move.l	%d1,(%a0)			| mov dword [edi], ebx
beginhline64:
	move.l	%d3,%d0				| mov eax, edx
	rol.l	%d7,%d0				| hmach3a: rol eax, ybits
	and.l	%d6,%d0				| hmach2a: and eax, mask
	sub.l	%a4,%d4				| hmach4a: sub esi, xinc
	subx.l	%d5,%d3				| hmach1a: sbb edx, yinc
	subq.l	#4,%a0				| sub edi, 4
	move.b	(%a2,%d0.l),%d2			| hoffs4: mov cl, byte [eax+bufplc]
	move.l	%d3,%d0				| mov eax, edx

	rol.l	%d7,%d0				| hmach3b: rol eax, ybits
	and.l	%d6,%d0				| hmach2b: and eax, mask
	sub.l	%a4,%d4				| hmach4b: sub esi, xinc
	subx.l	%d5,%d3				| hmach1b: sbb edx, yinc
	move.b	(%a3,%d2.l),%d1			| pal4: mov bh, byte [ecx+palookup]
	ror.l	#8,%d1
	move.b	(%a2,%d0.l),%d2			| hoffs5: mov cl, byte [eax+bufplc]
	move.l	%d3,%d0				| mov eax, edx

	rol.l	%d7,%d0				| hmach3c: rol eax, ybits
	move.b	(%a3,%d2.l),%d1			| pal5: mov bl, byte [ecx+palookup]
	ror.l	#8,%d1				| shl ebx, 16
	and.l	%d6,%d0				| hmach2c: and eax, mask
	sub.l	%a4,%d4				| hmach4c: sub esi, xinc
	subx.l	%d5,%d3				| hmach1c: sbb edx, yinc
	move.b	(%a2,%d0.l),%d2			| hoffs6: mov cl, byte [eax+bufplc]

	move.l	%d3,%d0				| mov eax, edx
	|(

	rol.l	%d7,%d0				| hmach3d: rol eax, ybits
	and.l	%d6,%d0				| hmach2d: and eax, mask
	sub.l	%a4,%d4				| hmach4d: sub esi, xinc
	subx.l	%d5,%d3				| hmach1d: sbb edx, yinc
	move.b	(%a3,%d2.l),%d1			| pal6: mov bh, byte [ecx+palookup]
	ror.l	#8,%d1
	move.b	(%a2,%d0.l),%d2			| hoffs7: mov cl, byte [eax+bufplc]
	move.b	(%a3,%d2.l),%d1			| pal7: mov bl, byte [ecx+palookup]
	ror.l	#8,%d1
	subq.l	#4,%a1				| sub ebp, 4
	move.l	%a1,%d0
	bpl.b	prebeginhline64			| jnc prebeginhline64
skipthe4byte:

	btst	#1,%d0				| test ebp, 2
	beq.b	skipdrawthe2
	move.w	%d1,2(%a0)			| rol ebx, 16 / mov word [edi+2], bx
	subq.l	#2,%a0				| sub edi, 2
	swap	%d1
skipdrawthe2:
	btst	#0,%d0				| test ebp, 1
	beq.b	skipdrawthe1
	move.b	%d1,3(%a0)			| shr ebx, 24 / mov byte [edi+3], bl
skipdrawthe1:

	CDECLEND	%d2-%d7/%a2-%a5
	rts

shorthline:
	move.l	%a1,%d0				| test ebp, ebp
	beq.b	endshorthline
begshorthline:
	HPIX					| hxsiz4, hysiz4, hoffs4, pal8
	move.b	%d1,(%a0)			| mov byte [edi], bl
	subq.l	#1,%a0				| dec edi
	subq.l	#1,%a1				| dec ebp
	move.l	%a1,%d0
	bne.b	begshorthline			| jnz begshorthline
endshorthline:
	CDECLEND	%d2-%d7/%a2-%a5
	rts
#undef SAVED

	.bss
	.balign	4
hlinevars:
machxbits:	.long	0
hxsiz:		.long	0
hysiz:		.long	0
hnegysiz:	.long	0
hoffs:		.long	0
hmach2:		.long	0
hpal:		.long	0
hmach4:		.long	0
hmach1:		.long	0
fixchain:	.long	0

	.text

	ALIGN
setupvlineasm:
	move.l	ARG(0,0),%d0
	| First for VLINEASM1, then for VLINEASM4
	move.l	%d0,mach3a			| premach3a, mach3a: shift
	move.l	%d0,machvsh			| machvsh1/3/5/6: 32-sh, machvsh7/9-12: sh,
						| machvsh2/4: (1<<sh)-1, machvsh8: 16-sh
	rts


	ALIGN
setupmvlineasm:
	move.l	ARG(0,0),maskmach3a	| maskmach3a, machmv13-16
	rts


	ALIGN
setuptvlineasm:
	move.l	ARG(0,0),transmach3a
	rts


	| eax=vinc, ebx=paloffs, ecx=cnt, edx=vplc, esi=bufplc, edi=p
	|
	| d0: vinc (eax)          d4: shift (mach3a)
	| d1: temp (ebx)          d5: bytes per line (fixchain)
	| d2: cnt (ecx)           a0: p (edi)
	| d3: vplc (edx)          a1: paloffs (ebp)
	|                         a2: bufplc (esi)
	.macro	VLINE1BEGIN shift
	CDECLBEGIN	%d2-%d5/%a2
	move.l	ARG(0,5),%d0
	move.l	ARG(1,5),%a1
	move.l	ARG(2,5),%d2
	move.l	ARG(3,5),%d3
	move.l	ARG(4,5),%a2
	move.l	ARG(5,5),%a0
	move.l	\shift,%d4
	move.l	fixchain,%d5
	.endm

	ALIGN
prevlineasm1:
	VLINE1BEGIN	mach3a
	tst.l	%d2				| test ecx, ecx
	bne.b	vlineasm1_nosetup

	add.l	%d3,%d0				| add eax, edx
	lsr.l	%d4,%d3				| premach3a: shr edx, 32
	move.b	(%a2,%d3.l),%d3			| mov dl, byte [esi+edx]
	move.b	(%a1,%d3.l),(%a0)		| mov cl, byte [ebx+edx] / mov byte [edi], cl
	CDECLEND	%d2-%d5/%a2
	rts


	ALIGN
vlineasm1:
	VLINE1BEGIN	mach3a
vlineasm1_nosetup:
	addq.l	#1,%d2				| inc ecx
	sub.l	%d5,%a0				| fixchain1a: sub edi, 320
beginvline:
	move.l	%d3,%d1				| mov ebx, edx
	lsr.l	%d4,%d1				| mach3a: shr ebx, 32
	add.l	%d5,%a0				| fixchain1b: add edi, 320
	move.b	(%a2,%d1.l),%d1			| mov bl, byte [esi+ebx]
	add.l	%d0,%d3				| add edx, eax
	move.b	(%a1,%d1.l),(%a0)		| mov bl, byte [ebp+ebx] / mov byte [edi], bl
	subq.l	#1,%d2				| dec ecx
	bne.b	beginvline			| jnz short beginvline
	move.l	%d3,%d0				| mov eax, edx
	CDECLEND	%d2-%d5/%a2
	rts


	ALIGN
mvlineasm1:
	VLINE1BEGIN	maskmach3a
beginmvline:
	move.l	%d3,%d1				| mov ebx, edx
	lsr.l	%d4,%d1				| maskmach3a: shr ebx, 32
	move.b	(%a2,%d1.l),%d1			| mov bl, byte [esi+ebx]
	cmp.b	#255,%d1			| cmp bl, 255
	beq.b	skipmask1
	move.b	(%a1,%d1.l),(%a0)		| maskmach3c: mov bl, [ebp+ebx] / mov byte [edi], bl
skipmask1:
	add.l	%d0,%d3				| add edx, eax
	add.l	%d5,%a0				| fixchain1m: add edi, 320
	subq.l	#1,%d2				| sub ecx, 1
	bcc.b	beginmvline			| jnc short beginmvline

	move.l	%d3,%d0				| mov eax, edx
	CDECLEND	%d2-%d5/%a2
	rts


	ALIGN
fixtransluscence:
	move.l	ARG(0,0),transmach4	| transmach4, tmach1-4, tran2traa-d
	rts


	| The x86 versions patch the opcodes at transrev0-17 to swap the
	| roles of the screen pixel and the palette lookup in the
	| translucency table index. Here a flag selects between two
	| copies of each loop.
	ALIGN
settransnormal:
	clr.l	transrev
	rts


	ALIGN
settransreverse:
	move.l	#1,transrev
	rts


	| eax=vinc, ebx=paloffs, ecx=cnt, edx=vplc, esi=bufplc, edi=p
	|
	| d0: transluc index (eax)  d5: bytes per line (fixchain)
	| d1: temp (ebx)            d6: vinc (ebp)
	| d2: cnt (ecx)             a0: p (edi)
	| d3: vplc (edx)            a1: paloffs (transmach3c)
	| d4: shift (transmach3a)   a2: bufplc (esi)
	|                           a3: transluc (transmach4)
	.macro	TVLINE1LOOP name, rev
\name:
	move.l	%d3,%d1				| mov ebx, edx
	lsr.l	%d4,%d1				| transmach3a: shr ebx, 32
	move.b	(%a2,%d1.l),%d1			| mov bl, byte [esi+ebx]
	cmp.b	#255,%d1			| cmp bl, 255
	beq.b	1f				| je short skiptrans1
	.if \rev
	move.b	(%a1,%d1.l),%d0			| transrev0: mov ah, [ebx+paloffs]
	lsl.w	#8,%d0
	move.b	(%a0),%d0			| transrev1: mov al, byte [edi]
	.else
	move.b	(%a0),%d0			| transrev1: mov ah, byte [edi]
	lsl.w	#8,%d0
	move.b	(%a1,%d1.l),%d0			| transrev0/transmach3c: mov al, [ebx+paloffs]
	.endif
	move.b	(%a3,%d0.l),(%a0)		| transmach4: mov al, byte [eax+_transluc] / mov byte [edi], al
1:						| skiptrans1:
	add.l	%d6,%d3				| add edx, ebp
	add.l	%d5,%a0				| fixchain1t: add edi, 320
	subq.l	#1,%d2				| dec ecx
	bne.b	\name				| jnz short begintvline
	.endm

	ALIGN
tvlineasm1:
	CDECLBEGIN	%d2-%d6/%a2-%a3
	move.l	ARG(0,7),%d6			| mov ebp, eax
	move.l	ARG(1,7),%a1			| mov dword [transmach3c+2], ebx
	move.l	ARG(2,7),%d2
	move.l	ARG(3,7),%d3
	move.l	ARG(4,7),%a2
	move.l	ARG(5,7),%a0
	move.l	transmach3a,%d4
	move.l	fixchain,%d5
	move.l	transmach4,%a3
	moveq	#0,%d0				| xor eax, eax
	addq.l	#1,%d2				| inc ecx
	tst.l	transrev
	bne.b	begintvline_rev
	TVLINE1LOOP	begintvline, 0
	bra.b	endtvline
	ALIGN
	TVLINE1LOOP	begintvline_rev, 1
endtvline:
	move.l	%d3,%d0				| mov eax, edx
	CDECLEND	%d2-%d6/%a2-%a3
	rts


	| ecx=cnt, edi=p
	|
	| The x86 version packs the four vplc/vinc pairs into three
	| registers with partial-register carries; here each column keeps
	| its own vplc and vinc, and the four pixels are packed into d1
	| for one longword store. Texture columns are at most 256 high, so
	| the texel index fits the low word of d0.
	|
	| d0: index, texel (ecx)  d4-d7: vince[0..3] (machvinc1-5)
	| d1: 4 pixels (ecx)      a0: end of the columns (machvline4end)
	| d2: p-end (edi)         a1: bufplce/palookupoffse pointer
	| d3: shift (machvsh1)    a2-a5: vplce[0..3] (esi/ebp/edx halves)
	.macro	VL4COL i, vplc, vinc
	move.l	bufplce+4*\i,%a1
	move.l	\vplc,%d0			| mov ecx, esi
	lsr.l	%d3,%d0				| machvsh1: shr ecx, 32-sh
	move.b	(%a1,%d0.l),%d0			| machvbuf: mov cl, byte [ecx+bufplce]
	move.l	palookupoffse+4*\i,%a1
	lsl.l	#8,%d1
	add.l	\vinc,\vplc			| machvinc: add esi, vince
	move.b	(%a1,%d0.w),%d1			| machvpal: mov cl, byte [ecx+palookupoffse]
	.endm

	ALIGN
vlineasm4:
	CDECLBEGIN	%d2-%d7/%a2-%a5
	move.l	ARG(0,10),%d0
	move.l	(ylookup,%d0.l*4),%d2		| mov eax, dword [ylookup+ecx*4]
	move.l	ARG(1,10),%a0
	add.l	%d2,%a0				| add eax, edi / mov dword [machvline4end+2], eax
	neg.l	%d2				| sub edi, eax

	move.l	machvsh,%d3

	move.l	vince,%d4			| machvinc1-5
	move.l	vince+4,%d5
	move.l	vince+8,%d6
	move.l	vince+12,%d7

	move.l	vplce,%a2
	move.l	vplce+4,%a3
	move.l	vplce+8,%a4
	move.l	vplce+12,%a5

	ALIGN
beginvlineasm4:
	VL4COL	0, %a2, %d4
	VL4COL	1, %a3, %d5
	VL4COL	2, %a4, %d6
	VL4COL	3, %a5, %d7
	move.l	%d1,(%a0,%d2.l)			| machvline4end: mov dword [edi+end], ecx
	add.l	fixchain,%d2			| fixchain2a: add edi, bpl
	bcc.w	beginvlineasm4			| jnc short beginvlineasm4

	move.l	%a2,vplce			| mov dword [vplce], ebp
	move.l	%a3,vplce+4			| mov dword [vplce+4], ebp
	move.l	%a4,vplce+8			| mov dword [vplce+8], esi
	move.l	%a5,vplce+12			| mov dword [vplce+12], esi

	CDECLEND	%d2-%d7/%a2-%a5
	rts


	| ecx=cnt, edi=p
	|
	| The x86 version collects a 4-bit mask of opaque pixels and
	| jumps into a table of 16 store sequences (mvcase0-15); here
	| each pixel is stored on its own when it is not masked.
	|
	| d0: index, texel (eax)  d4-d7: vince[0..3] (machmv3/6/9/12)
	| d2: p-end (edi)         a0: end of the columns
	| d3: shift (machmv13)    a1: bufplce/palookupoffse pointer
	|                         a2-a5: vplce[0..3] (ecx/edx/esi/ebp)
	.macro	MVL4COL i, vplc, vinc
	move.l	bufplce+4*\i,%a1
	move.l	\vplc,%d0			| mov eax, ecx
	lsr.l	%d3,%d0				| machmv13-16: shr eax, 32
	move.b	(%a1,%d0.l),%d0			| machmv1/4/7/10: mov al, byte [eax+bufplce]
	move.l	palookupoffse+4*\i,%a1
	add.l	\vinc,\vplc			| machmv3/6/9/12: add ecx, vince
	cmp.b	#255,%d0			| cmp al, 255
	beq.b	1f				| adc dl, dl
	move.b	(%a1,%d0.w),\i(%a0,%d2.l)	| machmv2/5/8/11: mov bl, byte [eax+palookupoffs] / mvcase: mov byte [edi+i], bl
1:
	.endm

	ALIGN
mvlineasm4:
	CDECLBEGIN	%d2-%d7/%a2-%a5
	move.l	ARG(0,10),%d0			| the x86 counts the rows in cl and bh
	move.l	(ylookup,%d0.l*4),%d2
	move.l	ARG(1,10),%a0
	add.l	%d2,%a0
	neg.l	%d2

	move.l	maskmach3a,%d3

	move.l	vince,%d4
	move.l	vince+4,%d5
	move.l	vince+8,%d6
	move.l	vince+12,%d7

	move.l	vplce,%a2
	move.l	vplce+4,%a3
	move.l	vplce+8,%a4
	move.l	vplce+12,%a5

	ALIGN
beginmvlineasm4:
	MVL4COL	0, %a2, %d4
	MVL4COL	1, %a3, %d5
	MVL4COL	2, %a4, %d6
	MVL4COL	3, %a5, %d7
	add.l	fixchain,%d2			| fixchain2mb: add edi, 320
	bcc.w	beginmvlineasm4			| jz near endmvlineasm4
endmvlineasm4:

	move.l	%a2,vplce			| mov dword [vplce], ecx
	move.l	%a3,vplce+4			| mov dword [vplce+4], edx
	move.l	%a4,vplce+8			| mov dword [vplce+8], esi
	move.l	%a5,vplce+12			| mov dword [vplce+12], ebp

	CDECLEND	%d2-%d7/%a2-%a5
	rts

	.bss
	.balign	4
mach3a:		.long	0
machvsh:	.long	0
maskmach3a:	.long	0
transmach3a:	.long	0
transmach4:	.long	0
transrev:	.long	0

	.text

	| eax=paloffs, ebx=(xv>>16)*ysiz, ecx=xv<<16, edx=ysiz, esi=yv, edi=0
	.macro	SETUPSPRITEVLINE pal, mach1, mach2, mach3, mach5
	move.l	%d2,-(%sp)
	move.l	ARG(0,1),%d0
	move.l	ARG(1,1),%d1

	move.l	%d0,\pal

	move.l	ARG(4,1),%d0			| mov eax, esi		;xinc's
	move.l	%d0,%d2				| (edx is free once ysiz is read below)
	swap	%d0
	clr.w	%d0				| shl eax, 16
	move.l	%d0,\mach1			| smach1, smach4
	move.l	%d2,%d0				| mov eax, esi
	asr.l	#8,%d0
	asr.l	#8,%d0				| sar eax, 16
	add.l	%d1,%d0				| add eax, ebx		;watch out with ebx - it's passed
	move.l	%d0,\mach2
	add.l	ARG(3,1),%d0			| add eax, edx
	move.l	%d0,\mach5

	move.l	ARG(2,1),\mach3		| yinc's

	move.l	(%sp)+,%d2
	rts
	.endm

	ALIGN
setupspritevline:
	SETUPSPRITEVLINE spal, smach1, smach2, smach3, smach5


	| eax = 0, ebx = x, ecx = cnt, edx = y, esi = yplc, edi = p
	|
	| d0: texel (eax)          d6: smach2
	| d1: x (ebx)              d7: smach5
	| d2: cnt (ecx)            a0: p (edi)
	| d3: y (edx)              a2: bufplc (esi)
	| d4: offset from bufplc   a3: palookup (spal)
	| d5: smach1               a4: smach3
	|                          a5: bytes per line (fixchain1s)
	.macro	SPRITEVLINEBEGIN pal, mach1, mach2, mach3, mach5
	CDECLBEGIN	%d2-%d7/%a2-%a5
	move.l	ARG(0,10),%d0
	move.l	ARG(1,10),%d1
	move.l	ARG(2,10),%d2
	move.l	ARG(3,10),%d3
	move.l	ARG(4,10),%a2
	moveq	#0,%d4
	move.l	ARG(5,10),%a0
	move.l	\pal,%a3
	move.l	\mach1,%d5
	move.l	\mach2,%d6
	move.l	\mach3,%a4
	move.l	\mach5,%d7
	move.l	fixchain,%a5
	.endm

	ALIGN
spritevline:
	SPRITEVLINEBEGIN spal, smach1, smach2, smach3, smach5
	bra.b	spritevline_start
prestartsvline:
	add.l	%d5,%d1				| smach1: add ebx, xincshl16
	move.b	(%a2,%d4.l),%d0			| mov al, byte [esi]
	addx.l	%d6,%d4				| smach2: adc esi, xincshr16+yalwaysinc

startsvline:
	move.b	(%a3,%d0.l),(%a0)		| spal: mov al, [eax+palookup] / mov byte [edi], al
	add.l	%a5,%a0				| fixchain1s: add edi, 320

spritevline_start:
	subq.l	#1,%d2				| dec ecx
	beq.b	endsvline			| jz short endsvline
	add.l	%a4,%d3				| smach3: add edx, dayinc
	bcc.b	prestartsvline			| ja short prestartsvline	;jump if (no carry (add)) and (not zero (dec))!
	add.l	%d5,%d1				| smach4: add ebx, xincshl16
	move.b	(%a2,%d4.l),%d0			| mov al, byte [esi]
	addx.l	%d7,%d4				| smach5: adc esi, xincshr16+yalwaysinc+daydime
	bra.b	startsvline
endsvline:
	CDECLEND	%d2-%d7/%a2-%a5
	rts


	ALIGN
msetupspritevline:
	SETUPSPRITEVLINE mspal, msmach1, msmach2, msmach3, msmach5


	ALIGN
mspritevline:
	SPRITEVLINEBEGIN mspal, msmach1, msmach2, msmach3, msmach5
	bra.b	mspritevline_start
	| eax = 0, ebx = x, ecx = cnt, edx = y, esi = yplc, edi = p
mprestartsvline:
	add.l	%d5,%d1				| msmach1: add ebx, xincshl16
	move.b	(%a2,%d4.l),%d0			| mov al, byte [esi]
	addx.l	%d6,%d4				| msmach2: adc esi, xincshr16+yalwaysinc

mstartsvline:
	cmp.b	#255,%d0			| cmp al, 255
	beq.b	mskipsvline
	move.b	(%a3,%d0.l),(%a0)		| mspal: mov al, [eax+palookup] / mov byte [edi], al
mskipsvline:
	add.l	%a5,%a0				| mfixchain1s: add edi, 320

mspritevline_start:
	subq.l	#1,%d2				| dec ecx
	beq.b	mendsvline			| jz short mendsvline
	add.l	%a4,%d3				| msmach3: add edx, dayinc
	bcc.b	mprestartsvline			| ja short mprestartsvline	;jump if (no carry (add)) and (not zero (dec))!
	add.l	%d5,%d1				| msmach4: add ebx, xincshl16
	move.b	(%a2,%d4.l),%d0			| mov al, byte [esi]
	addx.l	%d7,%d4				| msmach5: adc esi, xincshr16+yalwaysinc+daydime
	bra.b	mstartsvline
mendsvline:
	CDECLEND	%d2-%d7/%a2-%a5
	rts


	ALIGN
tsetupspritevline:
	SETUPSPRITEVLINE tspal, tsmach1, tsmach2, tsmach3, tsmach5


	| eax = 0, ebx = x, ecx = cnt, edx = y, esi = yplc, edi = p
	|
	| d0: texel (eax)          d6: tsmach2
	| d1: transluc index (ebx) d7: x (ebp)
	| d2: tsmach5              a0: p (edi)
	| d3: y (edx)              a1: transluc (tmach4)
	| d4: offset from bufplc   a2: bufplc (esi)
	| d5: cnt (ecx)            a3: palookup (tspal)
	|                          a4: tsmach3
	|                          a5: bytes per line (tfixchain1s)
	|                          a6: tsmach1
	.macro	TSPRITEVLINE rev
	bra.b	tenterspritevline\rev
	ALIGN
tprestartsvline\rev:
	add.l	%a6,%d7				| tsmach1: add ebp, xincshl16
	move.b	(%a2,%d4.l),%d0			| mov al, byte [esi]
	addx.l	%d6,%d4				| tsmach2: adc esi, xincshr16+yalwaysinc

tstartsvline\rev:
	cmp.b	#255,%d0			| cmp al, 255
	beq.b	tskipsvline\rev
	.if \rev
	move.b	(%a3,%d0.l),%d1			| transrev3/tspal: mov bh, [eax+palookup]
	lsl.w	#8,%d1
	move.b	(%a0),%d1			| transrev2: mov bl, byte [edi]
	.else
	move.b	(%a0),%d1			| transrev2: mov bh, byte [edi]
	lsl.w	#8,%d1
	move.b	(%a3,%d0.l),%d1			| transrev3/tspal: mov bl, [eax+palookup]
	.endif
	move.b	(%a1,%d1.l),(%a0)		| tmach4: mov al, byte [ebx+_transluc] / mov byte [edi], al
tskipsvline\rev:
	add.l	%a5,%a0				| tfixchain1s: add edi, 320

tenterspritevline\rev:
	subq.l	#1,%d5				| dec ecx
	beq.b	tendsvline\rev			| jz short tendsvline
	add.l	%a4,%d3				| tsmach3: add edx, dayinc
	bcc.b	tprestartsvline\rev		| ja short tprestartsvline	;jump if (no carry (add)) and (not zero (dec))!
	add.l	%a6,%d7				| tsmach4: add ebp, xincshl16
	move.b	(%a2,%d4.l),%d0			| mov al, byte [esi]
	addx.l	%d2,%d4				| tsmach5: adc esi, xincshr16+yalwaysinc+daydime
	bra.b	tstartsvline\rev
tendsvline\rev:
	.endm

	ALIGN
tspritevline:
	CDECLBEGIN	%d2-%d7/%a2-%a6
	move.l	ARG(0,11),%d0
	move.l	ARG(1,11),%d7			| mov ebp, ebx
	move.l	ARG(2,11),%d5
	move.l	ARG(3,11),%d3
	move.l	ARG(4,11),%a2
	moveq	#0,%d4
	move.l	ARG(5,11),%a0
	move.l	transmach4,%a1
	move.l	tspal,%a3
	move.l	tsmach1,%a6
	move.l	tsmach2,%d6
	move.l	tsmach3,%a4
	move.l	tsmach5,%d2
	move.l	fixchain,%a5
	moveq	#0,%d1				| xor ebx, ebx
	tst.l	transrev
	bne.b	tspritevline_rev
	TSPRITEVLINE	0
	bra.b	tendspritevline
tspritevline_rev:
	TSPRITEVLINE	1
tendspritevline:
	CDECLEND	%d2-%d7/%a2-%a6
	rts

	.bss
	.balign	4
spal:		.long	0
smach1:		.long	0
smach2:		.long	0
smach3:		.long	0
smach5:		.long	0
mspal:		.long	0
msmach1:	.long	0
msmach2:	.long	0
msmach3:	.long	0
msmach5:	.long	0
tspal:		.long	0
tsmach1:	.long	0
tsmach2:	.long	0
tsmach3:	.long	0
tsmach5:	.long	0

	.text

	| eax=logx, ebx=logy
	.macro	SETHLINESHIFT sh1, sh2, negsh2
	move.l	ARG(0,0),%d0
	move.l	ARG(1,0),%d1
	neg.l	%d0				| neg al
	and.l	#31,%d0
	move.l	%d0,\sh1			| msh1d/3d/5d: 32-logx
	move.l	%d1,\sh2			| msh2d/4d/6d: logy
	moveq	#32,%d0
	sub.l	%d1,%d0
	move.l	%d0,\negsh2			| 32-logy, for the shld emulation
	rts
	.endm

	ALIGN
msethlineshift:
	SETHLINESHIFT msh1d, msh2d, mnegsh2d


	| asm1 = bxinc
	| asm2 = byinc
	| asm3 = shadeoffs
	| eax = picoffs
	| ebx = bx
	| ecx = cnt
	| edx = ?
	| esi = by
	| edi = p
	|
	| d0: texel 2 (ch/al)      d5: 32-logx (msh1d)
	| d1: bx+bxinc, then       d6: bx (ebp)
	|     2 pixels (ebx)       d7: logy (msh2d)
	| d2: cnt<<16 | 32-logy    a0: p (edi)
	|     (ecx: cnt<<16)       a2: picoffs (mmach1d)
	| d3: texel 1 (cl)         a3: shadeoffs (mmach2d)
	| d4: by (esi)             a4: bxinc (mmach3d)
	|                          a5: byinc (mmach4d)
	|                          a6: 2<<16, the count step of a pair
	.macro	MHLINEBEGIN buf, pal, xinc, yinc, sh1, sh2, negsh2
	CDECLBEGIN	%d2-%d7/%a2-%a6
	move.l	ARG(1,11),%d1
	move.l	ARG(2,11),%d2
	move.l	ARG(4,11),%d4
	move.l	ARG(5,11),%a0
	move.l	#131072,%a6
	move.l	\buf,%a2
	move.l	\pal,%a3
	move.l	\xinc,%a4
	move.l	\yinc,%a5
	move.l	\sh1,%d5
	move.l	\sh2,%d7
	move.b	\negsh2+3,%d2			| the low byte of ecx is scratch on x86
	.endm

	| Both texels of a pair: bx (\bx) and bx+bxinc (\bxnext) are turned
	| into texture offsets, the texels land in d3 and d0 with the upper
	| bits clear.
	.macro	MHLINEPAIR
	move.l	%d6,%d1				| mmach3d: lea ebx, [ebp+bxinc]
	add.l	%a4,%d1
	lsr.l	%d5,%d6				| msh3d: shr ebp, 32-logx
	lsl.l	%d7,%d6				| msh4d: shld ebp, esi, logy
	move.l	%d4,%d3
	lsr.l	%d2,%d3
	or.l	%d3,%d6
	add.l	%a5,%d4				| mmach4d: add esi, byinc
	moveq	#0,%d3
	move.b	(%a2,%d6.l),%d3			| mmach1d: mov cl, byte [ebp+picoffs]
	move.l	%d1,%d6				| mmach7d: lea ebp, [ebx+bxinc]
	add.l	%a4,%d6

	lsr.l	%d5,%d1				| msh5d: shr ebx, 32-logx
	lsl.l	%d7,%d1				| msh6d: shld ebx, esi, logy
	move.l	%d4,%d0
	lsr.l	%d2,%d0
	or.l	%d0,%d1
	add.l	%a5,%d4				| mmach8d: add esi, byinc
	moveq	#0,%d0
	move.b	(%a2,%d1.l),%d0			| mmach5d: mov ch, byte [ebx+picoffs]
	.endm

	ALIGN
mhline:
	move.l	ARG(0,0),mmach1d	| mmach1d, mmach5d, mmach9d
	move.l	asm3,mmach2d		| mmach2d, mmach2da, mmach2db, mmach6d, mmach10d
	move.l	asm1,mmach3d		| mmach3d, mmach7d
	move.l	asm2,mmach4d		| mmach4d, mmach8d
						| falls into mhlineskipmodify


	ALIGN
mhlineskipmodify:
	MHLINEBEGIN mmach1d, mmach2d, mmach3d, mmach4d, msh1d, msh2d, mnegsh2d
mhlineskipmodify_nosetup:

	moveq	#0,%d0				| xor eax, eax
	move.l	%d1,%d6				| mov ebp, ebx

	btst	#16,%d2				| test ecx, 00010000h
	bne.b	mbeghline

	lsr.l	%d5,%d1				| msh1d: shr ebx, 32-logx
	lsl.l	%d7,%d1				| msh2d: shld ebx, esi, logy
	move.l	%d4,%d3
	lsr.l	%d2,%d3
	or.l	%d3,%d1
	add.l	asm1,%d6			| add ebp, dword [asm1]
	move.b	(%a2,%d1.l),%d0			| mmach9d: mov al, byte [ebx+picoffs]
	add.l	asm2,%d4			| add esi, dword [asm2]
	cmp.b	#255,%d0			| cmp al, 255
	beq.b	mskip5

	move.b	(%a3,%d0.l),(%a0)		| mmach10d: mov cl, byte [eax+shadeoffs] / mov byte [edi], cl
mskip5:
	addq.l	#1,%a0				| inc edi
	sub.l	#65536,%d2			| sub ecx, 65536
	bcs.w	mendhline			| jc near mendhline
	bra.b	mbeghline

	ALIGN
mpreprebeghline:				| 1st only
	move.b	(%a3,%d3.l),(%a0)		| mov al, cl / mmach2d: mov al, byte [eax+shadeoffs] / mov byte [edi], al

mprebeghline:
	addq.l	#2,%a0				| add edi, 2
	sub.l	%a6,%d2				| sub ecx, 131072
	bcs.w	mendhline			| jc near mendhline
mbeghline:
	MHLINEPAIR

	cmp.b	#255,%d3			| cmp cl, 255
	beq.b	mskip1
	cmp.b	#255,%d0			| cmp ch, 255
	beq.b	mpreprebeghline

	move.b	(%a3,%d3.l),%d1			| BOTH: mov al, cl / mmach2da: mov bl, byte [eax+shadeoffs]
	lsl.w	#8,%d1
	move.b	(%a3,%d0.l),%d1			| mov al, ch / mmach2db: mov bh, byte [eax+shadeoffs]
	move.w	%d1,(%a0)			| mov word [edi], bx
	addq.l	#2,%a0				| add edi, 2
	sub.l	%a6,%d2				| sub ecx, 131072
	bcc.b	mbeghline			| jnc short mbeghline
	bra.b	mendhline
mskip1:						| 2nd only
	cmp.b	#255,%d0			| cmp ch, 255
	beq.b	mprebeghline

	move.b	(%a3,%d0.l),1(%a0)		| mov al, ch / mmach6d: mov al, byte [eax+shadeoffs] / mov byte [edi+1], al
	addq.l	#2,%a0				| add edi, 2
	sub.l	%a6,%d2				| sub ecx, 131072
	bcc.b	mbeghline			| jnc short mbeghline
mendhline:

	CDECLEND	%d2-%d7/%a2-%a6
	rts


	ALIGN
tsethlineshift:
	SETHLINESHIFT tsh1d, tsh2d, tnegsh2d


	| asm1 = bxinc
	| asm2 = byinc
	| asm3 = shadeoffs
	| eax = picoffs
	| ebx = bx
	| ecx = cnt
	| edx = ?
	| esi = by
	| edi = p
	|
	| Registers as in mhline, plus a1: transluc (tmach1-3). The
	| translucency index (edx) is built in d1 once the texels are in.
	.macro	THLINE rev
	moveq	#0,%d0				| xor eax, eax
	move.l	%d1,%d6				| mov ebp, ebx

	btst	#16,%d2				| test ecx, 00010000h
	bne.b	tbeghline\rev

	lsr.l	%d5,%d1				| tsh1d: shr ebx, 32-logx
	lsl.l	%d7,%d1				| tsh2d: shld ebx, esi, logy
	move.l	%d4,%d3
	lsr.l	%d2,%d3
	or.l	%d3,%d1
	add.l	asm1,%d6			| add ebp, dword [asm1]
	move.b	(%a2,%d1.l),%d0			| tmach9d: mov al, byte [ebx+picoffs]
	add.l	asm2,%d4			| add esi, dword [asm2]
	cmp.b	#255,%d0			| cmp al, 255
	beq.b	tskip5\rev

	moveq	#0,%d1
	.if \rev
	move.b	(%a3,%d0.l),%d1			| transrev4/tmach10d: mov dh, byte [eax+shadeoffs]
	lsl.w	#8,%d1
	move.b	(%a0),%d1			| transrev5: mov dl, byte [edi]
	.else
	move.b	(%a0),%d1			| transrev5: mov dh, byte [edi]
	lsl.w	#8,%d1
	move.b	(%a3,%d0.l),%d1			| transrev4/tmach10d: mov dl, byte [eax+shadeoffs]
	.endif
	move.b	(%a1,%d1.l),(%a0)		| tmach1: mov al, byte [edx+_transluc] / mov byte [edi], al
tskip5\rev:
	addq.l	#1,%a0				| inc edi
	sub.l	#65536,%d2			| sub ecx, 65536
	bcs.w	tendhline\rev			| jc near tendhline
	bra.b	tbeghline\rev

	ALIGN
tprebeghline\rev:
	addq.l	#2,%a0				| add edi, 2
	sub.l	%a6,%d2				| sub ecx, 131072
	bcs.w	tendhline\rev			| jc short tendhline
tbeghline\rev:
	MHLINEPAIR				| tmach3d, tsh3d, tsh4d, tmach4d, tmach1d,
						| tmach7d, tsh5d, tsh6d, tmach8d, tmach5d

	cmp.b	#255,%d3			| cmp cx, 0ffffh
	bne.b	1f
	cmp.b	#255,%d0
	beq.b	tprebeghline\rev		| je short tprebeghline
1:
	cmp.b	#255,%d3			| cmp cl, 255
	beq.b	tskip1\rev
	moveq	#0,%d1				| mov bx, word [edi] / mov al, cl
	.if \rev
	move.b	(%a3,%d3.l),%d1			| transrev6/tmach2d: mov dh, byte [eax+shadeoffs]
	lsl.w	#8,%d1
	move.b	(%a0),%d1			| transrev7: mov dl, bl
	.else
	move.b	(%a0),%d1			| transrev7: mov dh, bl
	lsl.w	#8,%d1
	move.b	(%a3,%d3.l),%d1			| transrev6/tmach2d: mov dl, byte [eax+shadeoffs]
	.endif
	move.b	(%a1,%d1.l),(%a0)		| tmach2: mov al, byte [edx+_transluc] / mov byte [edi], al

	cmp.b	#255,%d0			| cmp ch, 255
	beq.b	tskip2\rev
tskip1\rev:
	moveq	#0,%d1				| mov al, ch
	.if \rev
	move.b	(%a3,%d0.l),%d1			| transrev8/tmach6d: mov dh, byte [eax+shadeoffs]
	lsl.w	#8,%d1
	move.b	1(%a0),%d1			| transrev9: mov dl, bh
	.else
	move.b	1(%a0),%d1			| transrev9: mov dh, bh
	lsl.w	#8,%d1
	move.b	(%a3,%d0.l),%d1			| transrev8/tmach6d: mov dl, byte [eax+shadeoffs]
	.endif
	move.b	(%a1,%d1.l),1(%a0)		| tmach3: mov al, byte [edx+_transluc] / mov byte [edi+1], al
tskip2\rev:

	addq.l	#2,%a0				| add edi, 2
	sub.l	%a6,%d2				| sub ecx, 131072
	bcc.w	tbeghline\rev			| jnc tbeghline
tendhline\rev:
	.endm

	ALIGN
thline:
	move.l	ARG(0,0),tmach1d	| tmach1d, tmach5d, tmach9d
	move.l	asm3,tmach2d		| tmach2d, tmach6d, tmach10d
	move.l	asm1,tmach3d		| tmach3d, tmach7d
	move.l	asm2,tmach4d		| tmach4d, tmach8d
						| falls into thlineskipmodify


	ALIGN
thlineskipmodify:
	MHLINEBEGIN tmach1d, tmach2d, tmach3d, tmach4d, tsh1d, tsh2d, tnegsh2d
	move.l	transmach4,%a1			| tmach1, tmach2, tmach3
thlineskipmodify_nosetup:
	tst.l	transrev
	bne.w	thline_rev
	THLINE	0
	bra.w	thline_end
thline_rev:
	THLINE	1
thline_end:

	CDECLEND	%d2-%d7/%a2-%a6
	rts

	.bss
	.balign	4
msh1d:		.long	0
msh2d:		.long	0
mnegsh2d:	.long	0
mmach1d:	.long	0
mmach2d:	.long	0
mmach3d:	.long	0
mmach4d:	.long	0
tsh1d:		.long	0
tsh2d:		.long	0
tnegsh2d:	.long	0
tmach1d:	.long	0
tmach2d:	.long	0
tmach3d:	.long	0
tmach4d:	.long	0

	.text

	| eax=shiftval, ebx=palookup1, ecx=palookup2
	ALIGN
setuptvlineasm2:
	move.l	ARG(0,0),tran2shra	| tran2shra, tran2shrb
	move.l	ARG(1,0),tran2pala	| tran2pala, tran2palc
	move.l	ARG(2,0),tran2palb	| tran2palb, tran2pald
	rts

	| Pass:   eax=vplc2, ebx=vinc1, ecx=bufplc1, edx=bufplc2, esi=vplc1, edi=p
	|         asm1=vinc2, asm2=pend
	| Return: asm1=vplc1, asm2=vplc2
	|
	| eax 0000000000  temp  temp
	| ebx 0000000000 odat2 odat1
	| ecx 0000000000000000 ndat1
	| edx 0000000000000000 ndat2
	| esi          vplc1
	| edi videoplc--------------
	| ebp          vplc2
	|
	| d0: transluc index 1 (eax)  d7: videoplc-pend (edi), the
	| d1: transluc index 2 (ebx)      loop condition
	| d2: ndat1 (ecx)
	| d3: ndat2 (edx)             a1: bytes per line (fixchaint2a)
	| d4: vplc1 (esi)             a2: bufplc1 (tran2bufa)
	| d5: vplc2 (ebp)             a3: bufplc2 (tran2bufb)
	| d6: globalshift (tran2shra) a4: palookup1 (tran2pala)
	| a0: pend (tran2edia-f)      a5: palookup2 (tran2palb)
	|                             a6: transluc (tran2traa)
	.macro	TVLINE2 rev
	bra.b	begintvline2\rev

	ALIGN
	| LEFT ONLY
skipdraw2\rev:
	.if \rev
	move.b	(%a4,%d2.l),%d0			| transrev11/tran2palc: mov ah, byte [ecx+palookup1]
	lsl.w	#8,%d0
	move.b	(%a0,%d7.l),%d0			| transrev10/tran2edic: mov al, byte [edi+pend]	;getpixel
	.else
	move.b	(%a0,%d7.l),%d0			| transrev10/tran2edic: mov ah, byte [edi+pend]	;getpixel
	lsl.w	#8,%d0
	move.b	(%a4,%d2.l),%d0			| transrev11/tran2palc: mov al, byte [ecx+palookup1]
	.endif
	move.b	(%a6,%d0.l),(%a0,%d7.l)		| tran2trac: mov bl, byte [eax+_transluc] / tran2edid: mov byte [edi+pend-320], bl	;drawpixel
	add.l	%a1,%d7				| fixchaint2d: add edi, 320
	bcc.b	begintvline2\rev		| jnc short begintvline2
	bra.w	endtvline2\rev

skipdraw1\rev:
	cmp.b	#255,%d3			| cmp dl, 255
	bne.b	skipdraw3\rev
	add.l	%a1,%d7				| fixchaint2b: add edi, 320
	bcs.w	endtvline2\rev			| jc short endtvline2

begintvline2\rev:
	move.l	%d4,%d0				| mov eax, esi
	lsr.l	%d6,%d0				| tran2shra: shr eax, globalshift
	move.l	%d5,%d1				| mov ebx, ebp
	lsr.l	%d6,%d1				| tran2shrb: shr ebx, globalshift
	add.l	tran2inca,%d4			| tran2inca: add esi, vinc1
	add.l	tran2incb,%d5			| tran2incb: add ebp, vinc2
	move.b	(%a2,%d0.l),%d2			| tran2bufa: mov cl, byte [eax+bufplc1]
	move.b	(%a3,%d1.l),%d3			| tran2bufb: mov dl, byte [ebx+bufplc2]
	cmp.b	#255,%d2			| cmp cl, 255
	beq.b	skipdraw1\rev			| je short skipdraw1
	cmp.b	#255,%d3			| cmp dl, 255
	beq.b	skipdraw2\rev			| je short skipdraw2

	| mov ax        The transluscent reverse of both!
	| mov bl, ah
	| mov ah
	| mov bh

	| BOTH
	.if \rev
	move.b	(%a4,%d2.l),%d0			| transrev14/tran2pala: mov ah, byte [ecx+palookup1]
	lsl.w	#8,%d0
	move.b	(%a0,%d7.l),%d0			| transrev12/13/tran2edia: mov al, byte [edi+pend]
	move.b	(%a5,%d3.l),%d1			| transrev15/tran2palb: mov bh, byte [edx+palookup2]
	lsl.w	#8,%d1
	move.b	1(%a0,%d7.l),%d1		| mov bl, byte [edi+pend+1]
	.else
	move.b	(%a0,%d7.l),%d0			| transrev12/13/tran2edia: mov ah, byte [edi+pend]	;getpixels
	lsl.w	#8,%d0
	move.b	(%a4,%d2.l),%d0			| transrev14/tran2pala: mov al, byte [ecx+palookup1]
	move.b	1(%a0,%d7.l),%d1		| mov bh, byte [edi+pend+1]
	lsl.w	#8,%d1
	move.b	(%a5,%d3.l),%d1			| transrev15/tran2palb: mov bl, byte [edx+palookup2]
	.endif
	move.b	(%a6,%d0.l),%d0			| tran2traa: mov al, byte [eax+_transluc]
	move.b	(%a6,%d1.l),%d1			| tran2trab: mov ah, byte [ebx+_transluc]
	lsl.w	#8,%d0
	move.b	%d1,%d0
	move.w	%d0,(%a0,%d7.l)			| tran2edib: mov word [edi+pend-320], ax	;drawpixels
	add.l	%a1,%d7				| fixchaint2c: add edi, 320
	bcc.b	begintvline2\rev		| jnc short begintvline2
	bra.b	endtvline2\rev

	| RIGHT ONLY
skipdraw3\rev:
	.if \rev
	move.b	(%a5,%d3.l),%d0			| transrev17/tran2pald: mov ah, byte [edx+palookup2]
	lsl.w	#8,%d0
	move.b	1(%a0,%d7.l),%d0		| transrev16/tran2edie: mov al, byte [edi+pend+1]	;getpixel
	.else
	move.b	1(%a0,%d7.l),%d0		| transrev16/tran2edie: mov ah, byte [edi+pend+1]	;getpixel
	lsl.w	#8,%d0
	move.b	(%a5,%d3.l),%d0			| transrev17/tran2pald: mov al, byte [edx+palookup2]
	.endif
	move.b	(%a6,%d0.l),1(%a0,%d7.l)	| tran2trad: mov bl, byte [eax+_transluc] / tran2edif: mov byte [edi+pend+1-320], bl	;drawpixel
	add.l	%a1,%d7				| fixchaint2e: add edi, 320
	bcc.w	begintvline2\rev		| jnc short begintvline2

endtvline2\rev:
	.endm

	ALIGN
tvlineasm2:
	CDECLBEGIN	%d2-%d7/%a2-%a6

	move.l	ARG(0,11),%d5			| mov ebp, eax

	move.l	ARG(1,11),tran2inca	| mov dword [tran2inca+2], ebx
	move.l	asm1,tran2incb		| mov dword [tran2incb+2], eax

	move.l	ARG(2,11),%a2			| bufplc1
	move.l	ARG(3,11),%a3			| bufplc2
	move.l	ARG(4,11),%d4
	move.l	ARG(5,11),%d7
	move.l	asm2,%a0			| tran2edia-f: pend, pend-320, pend+1...
	sub.l	%a0,%d7				| sub edi, pend
	move.l	fixchain,%a1			| fixchaint2a-e

	move.l	tran2shra,%d6
	move.l	tran2pala,%a4
	move.l	tran2palb,%a5
	move.l	transmach4,%a6

	moveq	#0,%d0
	moveq	#0,%d1
	moveq	#0,%d2				| xor ecx, ecx
	moveq	#0,%d3				| xor edx, edx
	tst.l	transrev
	bne.w	tvlineasm2_rev
	TVLINE2	0
	bra.w	tvlineasm2_end
tvlineasm2_rev:
	TVLINE2	1
tvlineasm2_end:
	move.l	%d4,asm1			| mov dword [asm1], esi
	move.l	%d5,asm2			| mov dword [asm2], ebp

	CDECLEND	%d2-%d7/%a2-%a6
	rts

	.bss
	.balign	4
tran2shra:	.long	0
tran2pala:	.long	0
tran2palb:	.long	0
tran2inca:	.long	0
tran2incb:	.long	0

	.text

	| BITSOFPRECISION equ 3
	| BITSOFPRECISIONPOW equ 8
#define BITSOFPRECISION 3
#define BITSOFPRECISIONPOW 8

	| setupslopevlin2 and slopevlin2 are exported by a.nasm but nothing
	| calls them, so they are left out here.

	| eax=logylogx (al=logx, ah=logy), ebx=bufplc, ecx=pinc
	ALIGN
setupslopevlin:
	CDECLBEGIN	%d2-%d4
	move.l	ARG(0,3),%d0
	move.l	ARG(1,3),%d1
	move.l	ARG(2,3),%d2

	move.l	%d1,slopmach3			| ptr
	move.l	%d2,slopmach5			| pinc
						| slopmach6 (-pinc) is applied directly

	moveq	#1,%d3				| mov edx, 1
	moveq	#0,%d4
	move.b	%d0,%d4				| mov cl, al
	lsl.l	%d4,%d3				| shl edx, cl
	subq.l	#1,%d3				| dec edx
	move.w	%d0,%d4
	lsr.w	#8,%d4				| mov cl, ah
	lsl.l	%d4,%d3				| shl edx, cl
	move.l	%d3,slopmach7

	neg.l	%d4				| neg ah
	move.l	%d4,%d3
	and.l	#31,%d3
	move.l	%d3,slopmach2			| 32-logy

	sub.b	%d0,%d4				| sub ah, al
	and.l	#31,%d4
	move.l	%d4,slopmach1			| 32-logy-logx

	fmove.l	asm1,%fp0			| fild dword [asm1]
	fmove.s	%fp0,asm2			| fstp dword [asm2]

	CDECLEND	%d2-%d4
	rts


	| eax=p, ebx=i, ecx=slopaloffs, edx=cnt, esi=bx, edi=by
	|
	| The x86 version walks the slopalookup table with esp and keeps
	| the inner loop counter in the low byte of the x increment, which
	| perturbs xplc by up to 255 per pixel; here the increment is
	| applied exactly.
	|
	| d0: recip/yinc temp, then  d7: 32-logy (slopmach2)
	|     inner count (eax, cl)  a0: videopos (ebp)
	| d1: temp (ebx)             a1: slopaloffs+4 (esp, slopmach4)
	| d2: mask (slopmach7)       a2: palette pointer from the table
	| cnt (ebx) is counted down in asm4
	| d3: temp (edx)             a3: pinc (slopmach5)
	| d4: xplc (esi)             a4: bufplc (slopmach3)
	| d5: yplc (edi)             a5: yinc (eax)
	| d6: 32-logx-logy           a6: xinc (ecx)
	|     (slopmach1)            fp0: z, fp1: z step (asm2)
	ALIGN
slopevlin:
	CDECLBEGIN	%d2-%d7/%a2-%a6

	move.l	ARG(0,11),%a0
	move.l	ARG(1,11),%d1
	move.l	ARG(2,11),%a1			| sub ecx, esp / mov dword [slopmach4+3], ecx
	addq.l	#4,%a1
	move.l	ARG(3,11),asm4			| mov dword [asm4], ebx
	move.l	ARG(4,11),%d4
	move.l	ARG(5,11),%d5

	fmove.l	asm3,%fp0			| fild dword [asm3]
	fmove.s	asm2,%fp1
	move.l	slopmach5,%a3
	sub.l	%a3,%a0				| slopmach6: lea ebp, [eax-pinc]
	fadd.x	%fp1,%fp0			| fadd dword [asm2]

	move.l	%d1,asm1			| mov dword [asm1], ebx
	lsl.l	#3,%d1				| shl ebx, 3

	move.l	globalx3,%d0			| mov eax, dword [globalx3]
	move.l	globaly3,%d3			| mov ecx, dword [globaly3]
	muls.l	%d1,%d0				| imul eax, ebx
	muls.l	%d1,%d3				| imul ecx, ebx
	add.l	%d0,%d4				| add esi, eax
	add.l	%d3,%d5				| add edi, ecx

	move.l	slopmach3,%a4
	move.l	slopmach1,%d6
	move.l	slopmach2,%d7
	move.l	slopmach7,%d2
	ALIGN
bigslopeloop:
	fmove.s	%fp0,%d0			| fst dword [fpuasm] / mov eax, dword [fpuasm]
	add.l	%d0,%d0				| add eax, eax
	subx.l	%d3,%d3				| sbb edx, edx
	bfextu	%d0{#0:#8},%d1			| mov ecx, eax / shr ecx, 24
	bfextu	%d0{#8:#11},%d0			| and eax, 00ffe000h / shr eax, 11
	subq.b	#2,%d1				| sub cl, 2
	and.b	#31,%d1
	move.l	(reciptable,%d0.l*4),%d0	| mov eax, dword [reciptable+eax]
	lsr.l	%d1,%d0				| shr eax, cl
	eor.l	%d3,%d0				| xor eax, edx
	move.l	asm1,%d3			| mov edx, dword [asm1]
	move.l	globalx3,%d1			| mov ecx, dword [globalx3]
	move.l	%d0,asm1			| mov dword [asm1], eax
	sub.l	%d3,%d0				| sub eax, edx
	move.l	globaly3,%d3			| mov edx, dword [globaly3]
	muls.l	%d0,%d1				| imul ecx, eax
	move.l	%d1,%a6
	muls.l	%d3,%d0				| imul eax, edx
	move.l	%d0,%a5

	fadd.x	%fp1,%fp0			| fadd dword [asm2]

	moveq	#BITSOFPRECISIONPOW,%d0		| mov cl, BITSOFPRECISIONPOW
	cmp.l	asm4,%d0			| cmp ebx, BITSOFPRECISIONPOW
	ble.b	slopeskipmin			| jl short slopeskipmin
	move.l	asm4,%d0			| mov cl, bl
slopeskipmin:

	| eax: yinc.............
	| ebx:   0   0   0   ?
	| ecx: xinc......... cnt
	| edx:         ?
	| esi: xplc.............
	| edi: yplc.............
	| ebp:     videopos

	move.l	%d4,%d1				| mov ebx, esi
	move.l	%d5,%d3				| mov edx, edi

beginnerslopeloop:
	lsr.l	%d6,%d1				| slopmach1: shr ebx, 32-logx-logy
	add.l	%a6,%d4				| add esi, ecx
	lsr.l	%d7,%d3				| slopmach2: shr edx, 32-logy
	and.l	%d2,%d1				| slopmach7: and ebx, mask
	add.l	%a5,%d5				| add edi, eax
	move.l	-(%a1),%a2			| slopmach4: mov ebx, dword [esp+off] / sub esp, 4
	add.l	%d3,%d1
	add.l	%a3,%a0				| slopmach5: add ebp, pinc
	move.b	(%a4,%d1.l),%d3			| slopmach3: mov dl, byte [ebx+edx+ptr]
	move.l	%d4,%d1				| mov ebx, esi
	move.b	(%a2,%d3.l),(%a0)		| mov al, byte [ebx+edx] ;tptr / mov [ebp], al
	move.l	%d5,%d3				| mov edx, edi
	subq.l	#1,%d0				| dec cl
	bne.b	beginnerslopeloop		| jnz short beginnerslopeloop

	subq.l	#BITSOFPRECISIONPOW,asm4	| sub ebx, BITSOFPRECISIONPOW
	bgt.w	bigslopeloop			| jg near bigslopeloop

						| ffree st0: fp0 is caller saved

	CDECLEND	%d2-%d7/%a2-%a6
	rts

	.bss
	.balign	4
slopmach1:	.long	0
slopmach2:	.long	0
slopmach3:	.long	0
slopmach5:	.long	0
slopmach7:	.long	0

	.text

	| eax=xlo inc, ebx=ylo inc, ecx=xhi*tilesizy+yhi inc, edx=palookup, esi=tilesizy
	.macro	SETUPRHLINE m1, m2, m3, m4, m5
	move.l	ARG(0,0),\m1
	move.l	ARG(1,0),\m2
	move.l	ARG(2,0),\m3
	move.l	ARG(3,0),\m4
	move.l	ARG(4,0),\m5
	rts
	.endm

	ALIGN
setuprhlineasm4:
	SETUPRHLINE rmach1, rmach2, rmach3, rmach4, rmach5	| rmach1a-e ... rmach5a-e

	| Non power of 2, non masking, with palookup method #1 (6 clock cycles)
	| eax: dat dat dat dat
	| ebx:          bufplc
	| ecx:  0          dat
	| edx:  xlo
	| esi:  ylo
	| edi:  videopos/cnt
	| ebp:  tempvar
	| esp:
	|
	| d0: 4 pixels (eax)       d7: tilesizy (rmach5)
	| d1: offset from bufplc   a0: videopos (edi+vidcntoffs)
	|     (ebx)                a1: cnt (edi)
	| d2: texel (ecx)          a2: bufplc
	| d3: xlo (edx)
	| d4: ylo (esi)            a3: palookup (rmach4)
	| d5: tempvar (ebp)        a4: xlo inc (rmach1)
	| d6: xhi*tilesizy+yhi+ycarry (rmach3)
	|                          a5: ylo inc (rmach2)
	.macro	RHLINEBEGIN m1, m2, m3, m4, m5
	CDECLBEGIN	%d2-%d7/%a2-%a5
	move.l	ARG(0,10),%a1
	move.l	ARG(1,10),%a2
	moveq	#0,%d1
	move.l	ARG(3,10),%d3
	move.l	ARG(4,10),%d4
	move.l	ARG(5,10),%a0
	move.l	\m1,%a4
	move.l	\m2,%a5
	move.l	\m3,%d6
	move.l	\m4,%a3
	move.l	\m5,%d7
	moveq	#0,%d2
	.endm

	| Steps the texture position by one pixel: the x fraction borrow
	| selects tilesizy, the y fraction borrow goes into the pointer.
	.macro	RHSTEP
	sub.l	%a4,%d3				| rmach1: sub edx, xlo
	subx.l	%d5,%d5				| sbb ebp, ebp
	sub.l	%a5,%d4				| rmach2: sub esi, ylo
	subx.l	%d6,%d1				| rmach3: sbb ebx, xhi*tilesizy + yhi+ycarry
	and.l	%d7,%d5				| rmach5: and ebp, tilesizy
	sub.l	%d5,%d1				| sub ebx, ebp
	.endm

	ALIGN
rhlineasm4:
	RHLINEBEGIN rmach1, rmach2, rmach3, rmach4, rmach5

	move.l	%a1,%d0				| cmp eax, 0
	ble.w	endrhline			| jle near endrhline

						| rmach6a/b: the stores use the
						| predecremented video pointer
	and.l	#3,%d0				| test edi, 3
	beq.b	begrhline			| jz short begrhline

	ALIGN
startrhline1:
	move.b	(%a2,%d1.l),%d2			| mov cl, byte [ebx]		;bufplc
	RHSTEP					| rmach1e, rmach2e, rmach3e, rmach5e
	move.b	(%a3,%d2.l),-(%a0)		| rmach4e: mov al, byte [ecx+palookup] / rmach6b: mov byte [edi+vidcntoffs], al
	subq.l	#1,%a1				| dec edi
	move.l	%a1,%d5
	and.l	#3,%d5				| test edi, 3
	bne.b	startrhline1			| jnz short startrhline1
	move.l	%a1,%d5				| test edi, edi
	beq.w	endrhline			| jz near endrhline

begrhline:
	move.b	(%a2,%d1.l),%d2			| mov cl, byte [ebx]		;bufplc
	RHSTEP					| rmach1a, rmach2a, rmach3a, rmach5a

	sub.l	%a4,%d3				| rmach1b: sub edx, xlo
	subx.l	%d5,%d5				| sbb ebp, ebp
	move.b	(%a3,%d2.l),%d0			| rmach4a: mov ah, byte [ecx+palookup]
	ror.l	#8,%d0
	move.b	(%a2,%d1.l),%d2			| mov cl, byte [ebx]		;bufplc
	sub.l	%a5,%d4				| rmach2b: sub esi, ylo
	subx.l	%d6,%d1				| rmach3b: sbb ebx, xhi*tilesizy + yhi+ycarry
	and.l	%d7,%d5				| rmach5b: and ebp, tilesizy
	move.b	(%a3,%d2.l),%d0			| rmach4b: mov al, byte [ecx+palookup]
	ror.l	#8,%d0				| shl eax, 16
	sub.l	%d5,%d1				| sub ebx, ebp

	move.b	(%a2,%d1.l),%d2			| mov cl, byte [ebx]		;bufplc
	RHSTEP					| rmach1c, rmach2c, rmach3c, rmach5c

	sub.l	%a4,%d3				| rmach1d: sub edx, xlo
	subx.l	%d5,%d5				| sbb ebp, ebp
	move.b	(%a3,%d2.l),%d0			| rmach4c: mov ah, byte [ecx+palookup]
	ror.l	#8,%d0
	move.b	(%a2,%d1.l),%d2			| mov cl, byte [ebx]		;bufplc
	sub.l	%a5,%d4				| rmach2d: sub esi, ylo
	subx.l	%d6,%d1				| rmach3d: sbb ebx, xhi*tilesizy + yhi+ycarry
	and.l	%d7,%d5				| rmach5d: and ebp, tilesizy
	move.b	(%a3,%d2.l),%d0			| rmach4d: mov al, byte [ecx+palookup]
	ror.l	#8,%d0
	sub.l	%d5,%d1				| sub ebx, ebp

	move.l	%d0,-(%a0)			| rmach6a: mov dword [edi+vidcntoffs], eax
	subq.l	#4,%a1				| sub edi, 4
	move.l	%a1,%d5
	bne.w	begrhline			| jnz near begrhline
endrhline:

	CDECLEND	%d2-%d7/%a2-%a5
	rts


	ALIGN
setuprmhlineasm4:
	SETUPRHLINE rmmach1, rmmach2, rmmach3, rmmach4, rmmach5


	ALIGN
rmhlineasm4:
	RHLINEBEGIN rmmach1, rmmach2, rmmach3, rmmach4, rmmach5

	move.l	%a1,%d0				| cmp eax, 0
	ble.b	endrmhline			| jle short endrmhline

						| rmmach6: the store uses the
						| predecremented video pointer
	ALIGN
begrmhline:
	move.b	(%a2,%d1.l),%d2			| mov cl, byte [ebx]		;bufplc
	sub.l	%a4,%d3				| rmmach1: sub edx, xlo
	subx.l	%d5,%d5				| sbb ebp, ebp
	sub.l	%a5,%d4				| rmmach2: sub esi, ylo
	subx.l	%d6,%d1				| rmmach3: sbb ebx, xhi*tilesizy + yhi+ycarry
	and.l	%d7,%d5				| rmmach5: and ebp, tilesizy
	subq.l	#1,%a0
	cmp.b	#255,%d2			| cmp cl, 255
	beq.b	rmskip
	move.b	(%a3,%d2.l),(%a0)		| rmmach4: mov al, byte [ecx+palookup] / rmmach6: mov byte [edi+vidcntoffs], al
rmskip:
	sub.l	%d5,%d1				| sub ebx, ebp
	subq.l	#1,%a1				| dec edi
	move.l	%a1,%d5
	bne.b	begrmhline			| jnz short begrmhline
endrmhline:

	CDECLEND	%d2-%d7/%a2-%a5
	rts


	| eax=0, ebx=ylo inc, ecx=xhi*tilesizy+yhi inc, edx=palookup
	ALIGN
setupqrhlineasm4:
	move.l	%d2,-(%sp)
	move.l	ARG(1,1),%d1
	move.l	ARG(2,1),%d2
	move.l	%d1,qrmach2e
	move.l	%d2,qrmach3e
	moveq	#0,%d0				| xor edi, edi
	sub.l	%d2,%d0				| sub edi, ecx
	move.l	%d0,qrmach7			| qrmach7a, qrmach7b

	add.l	%d1,%d1				| add ebx, ebx
	addx.l	%d2,%d2				| adc ecx, ecx
	move.l	%d1,qrmach2a			| qrmach2a, qrmach2b
	move.l	%d2,qrmach3a			| qrmach3a, qrmach3b

	move.l	ARG(3,1),qrmach4	| qrmach4a-e

	move.l	(%sp)+,%d2
	rts

	| Non power of 2, non masking, with palookup method (FASTER BUT NO SBB'S)
	| eax: dat dat dat dat
	| ebx:          bufplc
	| ecx:  0          dat
	| edx:  0          dat
	| esi:  ylo
	| edi:  videopos/cnt
	| ebp:  ?
	| esp:
	|
	| d0: 4 pixels (eax)       a0: videopos (edi)
	| d1: offset from bufplc   a1: cnt (ebp)
	|     (ebx)                a2: bufplc
	| d2: texel (ecx)          a6: bufplc-(xhi*tilesizy+yhi) (qrmach7)
	| d3: texel (edx)
	| d4: ylo (esi)            a3: palookup (qrmach4)
	| d5: xhi*tilesizy+yhi inc a4: 2*ylo inc (qrmach2a)
	|     (qrmach3e)           a5: ylo inc (qrmach2e)
	| d6: 2*(xhi*tilesizy+yhi)+c (qrmach3a)
	ALIGN
qrhlineasm4:
	CDECLBEGIN	%d2-%d7/%a2-%a6
	move.l	ARG(0,11),%a1
	move.l	ARG(1,11),%a2
	moveq	#0,%d1
	move.l	ARG(4,11),%d4
	move.l	ARG(5,11),%a0
	move.l	qrmach3e,%d5
	move.l	qrmach3a,%d6
	move.l	%a2,%a6
	add.l	qrmach7,%a6			| qrmach7a, qrmach7b
	move.l	qrmach4,%a3
	move.l	qrmach2a,%a4
	move.l	qrmach2e,%a5
	moveq	#0,%d2
	moveq	#0,%d3

	move.l	%a1,%d0				| cmp eax, 0
	ble.b	endqrhline			| jle near endqrhline

	and.l	#3,%d0				| test ebp, 3
	beq.b	skipqrhline1			| jz short skipqrhline1

	ALIGN
startqrhline1:
	move.b	(%a2,%d1.l),%d2			| mov cl, byte [ebx]		;bufplc
	sub.l	%a5,%d4				| qrmach2e: sub esi, ylo
	subx.l	%d5,%d1				| qrmach3e: sbb ebx, xhi*tilesizy + yhi+ycarry
	subq.l	#1,%a1				| dec ebp
	move.b	(%a3,%d2.l),-(%a0)		| qrmach4e: mov al, byte [ecx+palookup] / dec edi / mov byte [edi], al	;vidcntoffs
	move.l	%a1,%d0
	and.l	#3,%d0				| test ebp, 3
	bne.b	startqrhline1			| jnz short startqrhline1
	move.l	%a1,%d0				| test ebp, ebp
	beq.b	endqrhline			| jz short endqrhline

skipqrhline1:
	move.b	(%a2,%d1.l),%d2			| mov cl, byte [ebx]		;bufplc
	ALIGN
begqrhline:
	move.b	(%a6,%d1.l),%d3			| qrmach7a: mov dl, byte [ebx-inc]	;bufplc
	sub.l	%a4,%d4				| qrmach2a: sub esi, 2*ylo
	subx.l	%d6,%d1				| qrmach3a: sbb ebx, 2*(xhi*tilesizy + yhi)+c
	move.b	(%a3,%d2.l),%d0			| qrmach4a: mov ah, byte [ecx+palookup]
	ror.l	#8,%d0
	move.b	(%a3,%d3.l),%d0			| qrmach4b: mov al, byte [edx+palookup]
	ror.l	#8,%d0				| shl eax, 16
	move.b	(%a2,%d1.l),%d2			| mov cl, byte [ebx]		;bufplc
	move.b	(%a6,%d1.l),%d3			| qrmach7b: mov dl, byte [ebx-inc]	;bufplc
	sub.l	%a4,%d4				| qrmach2b: sub esi, 2*ylo
	subx.l	%d6,%d1				| qrmach3b: sbb ebx, 2*(xhi*tilesizy + yhi)+c
	move.b	(%a3,%d2.l),%d0			| qrmach4c: mov ah, byte [ecx+palookup]
	ror.l	#8,%d0
	move.b	(%a3,%d3.l),%d0			| qrmach4d: mov al, byte [edx+palookup]
	ror.l	#8,%d0
	move.b	(%a2,%d1.l),%d2			| mov cl, byte [ebx]		;bufplc
	move.l	%d0,-(%a0)			| sub edi, 4 / mov dword [edi], eax
	subq.l	#4,%a1				| sub ebp, 4
	move.l	%a1,%d0
	bne.b	begqrhline			| jnz short begqrhline

endqrhline:

	CDECLEND	%d2-%d7/%a2-%a6
	rts

	.bss
	.balign	4
rmach1:		.long	0
rmach2:		.long	0
rmach3:		.long	0
rmach4:		.long	0
rmach5:		.long	0
rmmach1:	.long	0
rmmach2:	.long	0
rmmach3:	.long	0
rmmach4:	.long	0
rmmach5:	.long	0
qrmach2a:	.long	0
qrmach2e:	.long	0
qrmach3a:	.long	0
qrmach3e:	.long	0
qrmach4:	.long	0
qrmach7:	.long	0

	.text

	| eax=bytes per line, ebx=palookup
	ALIGN
setupdrawslab:
	move.l	ARG(0,0),voxbpl		| voxbpl1-8
	move.l	ARG(1,0),voxpal		| voxpal1-8
	rts

	| eax=dx, ebx=v, ecx=dy, edx=vi, esi=vptr, edi=p
	|
	| d0: pixel (eax)           d7: dy of the column (ecx pushed)
	| d1: v (ebx)               a0: p (edi)
	| d2: dy (ecx)              a1: p of the column (edi pushed)
	| d3: vi (edx)              a2: vptr (esi)
	| d4: p+dx (eax)            a3: palookup (voxpal)
	| d5: v>>16 (ebp)           a4: bytes per line (voxbpl)
	| d6: v of the column (ebx pushed)

	| One column of \w bytes, dy rows high. The x86 pushes ebx, ecx and
	| edi around each column and pops them afterwards; here the column
	| runs on copies.
	.macro	VOXCOL w, label
	move.l	%d1,%d6				| push ebx
	move.l	%d2,%d7				| push ecx
	move.l	%a0,%a1				| push edi
	.if \w == 1
	moveq	#0,%d0				| xor eax, eax
	.endif
\label:
	move.l	%d6,%d5				| mov ebp, ebx
	add.l	%d3,%d6				| add ebx, edx
	clr.w	%d5
	swap	%d5				| shr ebp, 16
	.if \w != 1
	moveq	#0,%d0				| xor eax, eax
	.endif
	move.b	(%a2,%d5.l),%d0			| mov al, byte [esi+ebp]
	.if \w == 1
	move.b	(%a3,%d0.l),(%a1)		| voxpal: mov al, byte [eax+palookup] / mov byte [edi], al
	.elseif \w == 2
	move.b	(%a3,%d0.l),%d0			| voxpal: mov al, byte [eax+palookup]
	mulu.w	#0x0101,%d0			| mov ah, al
	move.w	%d0,(%a1)			| mov word [edi], ax
	.else
	move.b	(%a3,%d0.l),%d0			| voxpal: mov al, byte [eax+palookup]
	mulu.l	#0x01010101,%d0			| mov ah, al / shl eax, 8 / mov al, ah / shl eax, 8 / mov al, ah
	move.l	%d0,(%a1)			| mov dword [edi], eax
	.endif
	add.l	%a4,%a1				| voxbpl: add edi, bpl
	subq.l	#1,%d7				| dec ecx
	bne.b	\label				| jnz near
	.endm

	ALIGN
drawslab:
	CDECLBEGIN	%d2-%d7/%a2-%a4
	move.l	ARG(0,9),%d0
	move.l	ARG(1,9),%d1
	move.l	ARG(2,9),%d2
	move.l	ARG(3,9),%d3
	move.l	ARG(4,9),%a2
	move.l	ARG(5,9),%a0
	move.l	voxpal,%a3
	move.l	voxbpl,%a4

	cmp.l	#2,%d0				| cmp eax, 2
	beq.b	voxbegdraw2			| je near voxbegdraw2
	bhi.b	voxskip2			| ja near voxskip2
	VOXCOL	1, voxbegdraw1			| voxpal1, voxbpl1
	bra.w	voxend

voxbegdraw2:
	VOXCOL	2, voxbegdraw2loop		| voxpal2, voxbpl2
	bra.w	voxend

voxskip2:
	cmp.l	#4,%d0				| cmp eax, 4
	bne.b	voxskip4			| jne near voxskip4
	VOXCOL	4, voxbegdraw4			| voxpal3, voxbpl3
	bra.w	voxend

voxskip4:
	move.l	%a0,%d4				| add eax, edi
	add.l	%d0,%d4

	move.l	%a0,%d0				| test edi, 1
	btst	#0,%d0
	beq.b	voxskipslab1			| jz near voxskipslab1
	cmp.l	%d4,%a0				| cmp edi, eax
	beq.b	voxskipslab1			| je near voxskipslab1

	VOXCOL	1, voxbegslab1			| voxpal4, voxbpl4
	addq.l	#1,%a0				| inc edi

voxskipslab1:
	move.l	%a0,%d0				| test edi, 2
	btst	#1,%d0
	beq.b	voxskipslab2			| jz near voxskipslab2
	move.l	%d4,%d0				| dec eax
	subq.l	#1,%d0
	cmp.l	%d0,%a0				| cmp edi, eax
	bge.b	voxskipslab2			| jge near voxskipslab2

	VOXCOL	2, voxbegslab2			| voxpal5, voxbpl5
	addq.l	#2,%a0				| add edi, 2

voxskipslab2:
	move.l	%d4,%d0				| mov eax, dword [esp]
	subq.l	#3,%d0				| sub eax, 3
	cmp.l	%d0,%a0				| cmp edi, eax
	bge.b	voxskipslab3			| jge near voxskipslab3

voxprebegslab3:
	VOXCOL	4, voxbegslab3			| voxpal6, voxbpl6
	addq.l	#4,%a0				| add edi, 4

	move.l	%d4,%d0				| mov eax, dword [esp]
	subq.l	#3,%d0				| sub eax, 3
	cmp.l	%d0,%a0				| cmp edi, eax
	blt.b	voxprebegslab3			| jl near voxprebegslab3

voxskipslab3:
	move.l	%d4,%d0				| mov eax, dword [esp]
	subq.l	#1,%d0				| dec eax
	cmp.l	%d0,%a0				| cmp edi, eax
	bge.b	voxskipslab4			| jge near voxskipslab4

	VOXCOL	2, voxbegslab4			| voxpal7, voxbpl7
	addq.l	#2,%a0				| add edi, 2

voxskipslab4:
	cmp.l	%d4,%a0				| pop eax / cmp edi, eax
	beq.b	voxskipslab5			| je near voxskipslab5

	VOXCOL	1, voxbegslab5			| voxpal8, voxbpl8

voxskipslab5:
voxend:
	CDECLEND	%d2-%d7/%a2-%a4
	rts

	| modify: loinc
	| eax: |  dat   |  dat   |   dat  |   dat  |
	| ebx: |      loplc1                       |
	| ecx: |      loplc2     |  cnthi |  cntlo |
	| edx: |--------|--------|--------| hiplc1 |
	| esi: |--------|--------|--------| hiplc2 |
	| edi: |--------|--------|--------| vidplc |
	| ebp: |--------|--------|--------|  hiinc |
	|
	| ebx=u, ecx=cnt, edx=uinc, esi=rptr, edi=p
	|
	| The x86 version keeps the count in cl/ch; here it is a plain
	| longword in d7.
	|
	| d0: 4 pixels (eax)       d5: hiinc (ebp)
	| d1: loplc1 (ebx)         d6: loinc (loinc1-4)
	| d2: loplc2 (ecx)         d7: cnt (cl, ch)
	| d3: hiplc1 (edx)         a0: vidplc (edi)
	| d4: hiplc2 (esi)         a2: rptr
	ALIGN
stretchhline:
	CDECLBEGIN	%d2-%d7/%a2
	move.l	ARG(1,7),%d1
	move.l	ARG(2,7),%d7
	move.l	ARG(4,7),%a2
	move.l	ARG(5,7),%a0

	move.l	%d1,%d0				| mov eax, ebx
	swap	%d1				| shl ebx, 16
	clr.w	%d1
	swap	%d0				| sar eax, 16
	ext.l	%d0
	move.l	%d1,%d2				| and ecx, 0000ffffh / or ecx, ebx

	move.l	%d0,%d4				| add esi, eax
	move.l	ARG(3,7),%d0			| mov eax, edx
	move.l	%d4,%d3				| mov edx, esi

	move.l	%d0,%d5				| mov ebp, eax
	swap	%d0				| shl eax, 16
	clr.w	%d0
	swap	%d5				| sar ebp, 16
	ext.l	%d5

	add.l	%d0,%d2				| add ecx, eax
	addx.l	%d5,%d4				| adc esi, ebp

	add.l	%d0,%d0				| add eax, eax
	addx.l	%d5,%d5				| adc ebp, ebp
	move.l	%d0,%d6				| loinc1-4

						| inc ch

begloop:
	move.b	(%a2,%d3.l),%d0			| mov al, [edx]
	sub.l	%d6,%d1				| loinc1: sub ebx, loinc
	subx.l	%d5,%d3				| sbb edx, ebp
	lsl.l	#8,%d0
	move.b	(%a2,%d4.l),%d0			| mov ah, [esi]
	sub.l	%d6,%d2				| loinc2: sub ecx, loinc
	subx.l	%d5,%d4				| sbb esi, ebp
	lsl.l	#8,%d0				| shl eax, 16
	sub.l	%d6,%d1				| loinc3: sub ebx, loinc
	move.b	(%a2,%d3.l),%d0			| mov al, [edx]
	subx.l	%d5,%d3				| sbb edx, ebp
	lsl.l	#8,%d0
	move.b	(%a2,%d4.l),%d0			| mov ah, [esi]
	sub.l	%d6,%d2				| loinc4: sub ecx, loinc
	subx.l	%d5,%d4				| sbb esi, ebp
	move.l	%d0,-(%a0)			| sub edi, 4 / mov [edi], eax
	subq.l	#1,%d7				| dec cl / dec ch
	bne.b	begloop				| jnz begloop

	CDECLEND	%d2-%d7/%a2
	rts


	| The x86 version detects the CPU and overlays sethlinesizes,
	| setpalookupaddress, setuphlineasm4, hlineasm4, setupvlineasm and
	| vlineasm4 with the Pentium Pro versions (prosethlinesizes,
	| prosetpalookupaddress, prohlineasm4, prosetupvlineasm,
	| provlineasm4). There is nothing to overlay here.
	ALIGN
mmxoverlay:
	rts

	.bss
	.balign	4
voxbpl:		.long	0
voxpal:		.long	0
