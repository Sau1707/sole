#include <stdint.h>
#include <math.h>
#include <stdio.h>

extern uint64_t raw_add(uint64_t, uint64_t);
extern uint64_t raw_sub(uint64_t, uint64_t);
extern uint64_t raw_mul(uint64_t, uint64_t);
extern int64_t raw_sdiv(int64_t, int64_t);
extern uint64_t raw_udiv(uint64_t, uint64_t);
extern int64_t raw_srem(int64_t, int64_t);
extern uint64_t raw_urem(uint64_t, uint64_t);
extern uint64_t raw_and(uint64_t, uint64_t);
extern uint64_t raw_or(uint64_t, uint64_t);
extern uint64_t raw_xor(uint64_t, uint64_t);
extern uint64_t raw_shl(uint64_t, uint64_t);
extern int64_t raw_ashr(int64_t, uint64_t);
extern uint64_t raw_lshr(uint64_t, uint64_t);
extern double raw_fadd(double, double);
extern double raw_fsub(double, double);
extern double raw_fmul(double, double);
extern double raw_fdiv(double, double);
extern double raw_frem(double, double);
extern double raw_fneg(double, double);
extern uint64_t raw_memory(uint64_t, uint64_t);
extern int64_t raw_branch(int64_t, int64_t);
extern uint64_t raw_popcount(uint64_t);
extern int64_t raw_roundtrip(int64_t);
extern uint64_t raw_float_eq(double, double);
extern uint64_t raw_aggregate(uint64_t, uint64_t);

#define REQUIRE(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "FAIL: %s\n", #condition); \
        return 1; \
    } \
} while (0)

int main(void) {
    REQUIRE(raw_add(UINT64_MAX, 1) == 0);
    REQUIRE(raw_sub(0, 1) == UINT64_MAX);
    REQUIRE(raw_mul(7, 6) == 42);
    REQUIRE(raw_sdiv(-9, 2) == -4);
    REQUIRE(raw_udiv(UINT64_MAX, 2) == UINT64_MAX / 2);
    REQUIRE(raw_srem(-9, 2) == -1);
    REQUIRE(raw_urem(UINT64_MAX, 2) == 1);
    REQUIRE(raw_and(12, 10) == 8);
    REQUIRE(raw_or(12, 10) == 14);
    REQUIRE(raw_xor(12, 10) == 6);
    REQUIRE(raw_shl(3, 4) == 48);
    REQUIRE(raw_ashr(-8, 2) == -2);
    REQUIRE(raw_lshr(UINT64_C(1) << 63, 1) == (UINT64_C(1) << 62));
    REQUIRE(raw_fadd(1.5, 2.0) == 3.5);
    REQUIRE(raw_fsub(1.5, 2.0) == -0.5);
    REQUIRE(raw_fmul(1.5, 2.0) == 3.0);
    REQUIRE(raw_fdiv(1.5, 2.0) == 0.75);
    REQUIRE(raw_frem(5.5, 2.0) == 1.5);
    REQUIRE(raw_fneg(1.5, 0.0) == -1.5);
    REQUIRE(raw_memory(20, 21) == 42);
    REQUIRE(raw_memory(UINT64_MAX, 0) == 0);
    REQUIRE(raw_branch(-5, 3) == -2);
    REQUIRE(raw_branch(5, 3) == 2);
    REQUIRE(raw_popcount(UINT64_MAX) == 64);
    REQUIRE(raw_popcount(0) == 0);
    REQUIRE(raw_roundtrip(-128) == -128);
    REQUIRE(raw_roundtrip(127) == 127);
    REQUIRE(raw_float_eq(1.5, 1.5) == 1);
    REQUIRE(raw_float_eq(1.5, 2.0) == 0);
    REQUIRE(raw_float_eq(NAN, NAN) == 0);
    REQUIRE(raw_aggregate(20, 22) == 42);
    return 0;
}
