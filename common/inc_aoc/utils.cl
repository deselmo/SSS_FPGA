#pragma once

#pragma OPENCL EXTENSION cl_intel_channels : enable

#define MAX(lhs, rhs) (((lhs) > (rhs)) ? (lhs) : (rhs))
#define MIN(lhs, rhs) (((lhs) > (rhs)) ? (rhs) : (lhs))

typedef uint __attribute__((__ap_int(8))) uint8_t;


#ifdef ARCH_EMULATOR
#define ifemu(block) do { block; } while(0);
#else
#define ifemu(block) do {} while(0);
#endif


#define NEXT_POWER_OF_2(v) (((((((v-1) | ((v-1) >> 1)) | (((v-1) | ((v-1) >> 1)) >> 2)) | ((((v-1) | ((v-1) >> 1)) | (((v-1) | ((v-1) >> 1)) >> 2)) >> 3)) | (((((v-1) | ((v-1) >> 1)) | (((v-1) | ((v-1) >> 1)) >> 2)) | ((((v-1) | ((v-1) >> 1)) | (((v-1) | ((v-1) >> 1)) >> 2)) >> 3)) >> 8)) | ((((((v-1) | ((v-1) >> 1)) | (((v-1) | ((v-1) >> 1)) >> 2)) | ((((v-1) | ((v-1) >> 1)) | (((v-1) | ((v-1) >> 1)) >> 2)) >> 3)) | (((((v-1) | ((v-1) >> 1)) | (((v-1) | ((v-1) >> 1)) >> 2)) | ((((v-1) | ((v-1) >> 1)) | (((v-1) | ((v-1) >> 1)) >> 2)) >> 3)) >> 8)) >> 16))+1)
