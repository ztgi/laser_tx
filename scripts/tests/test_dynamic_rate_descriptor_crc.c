#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "laser_dynamic_rate_descriptor.h"

int main(void)
{
    uint32_t words[LASER_DYN_DESC_WORDS];
    memset(words, 0, sizeof(words));
    words[LASER_DYN_WORD_MAGIC] = LASER_DYN_DESC_MAGIC;
    words[LASER_DYN_WORD_VERSION_COUNT] = LASER_DYN_DESC_VERSION_COUNT;
    words[LASER_DYN_WORD_SEQUENCE] = UINT32_C(0x12345678);
    if (laser_dyn_descriptor_crc32(words) != UINT32_C(0xDCF3D1B2)) {
        fprintf(stderr, "CRC mismatch: %08lx\n",
                (unsigned long)laser_dyn_descriptor_crc32(words));
        return 1;
    }
    puts("PASS: C descriptor CRC golden vector");
    return 0;
}
