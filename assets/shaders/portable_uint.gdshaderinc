// Exact low 32 bits of a product, using only byte-sized float products.
// Some older Adreno shader compilers reject 32-bit integer products in complex
// material control flow. Every intermediate integer here is <= 260100 and
// therefore exactly representable in float32; uint sums retain modulo 2^32.
uint ink_mul32(uint a,uint b){
 vec4 x=vec4(float(a&255u),float((a>>8u)&255u),float((a>>16u)&255u),float(a>>24u));
 vec4 y=vec4(float(b&255u),float((b>>8u)&255u),float((b>>16u)&255u),float(b>>24u));
 uint p0=uint(x.x*y.x);
 uint p1=uint(x.y*y.x+x.x*y.y);
 uint p2=uint(x.z*y.x+x.y*y.y+x.x*y.z);
 uint p3=uint(x.w*y.x+x.z*y.y+x.y*y.z+x.x*y.w);
 return p0+(p1<<8u)+(p2<<16u)+(p3<<24u);
}
