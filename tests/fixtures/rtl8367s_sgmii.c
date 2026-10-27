#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>

typedef uint32_t u32;
typedef int phy_interface_t;
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define FIELD_PREP(mask, val) (((unsigned int)(val) << __builtin_ctz(mask)) & (mask))
#define PHY_INTERFACE_MODE_SGMII 1
#define PHY_INTERFACE_MODE_2500BASEX 2
#define RTL8365MB_MAGIC_VALUE 0x0249
#define RTL8365MB_CHIP_RESET_REG 0x1322
#define RTL8365MB_EXT_PORT_MODE_SGMII 9
#define RTL8365MB_EXT_PORT_MODE_HSGMII 10
#define RTL8365MB_DIGITAL_INTERFACE_SELECT_REG(id) ((id) == 2 ? 0x13c3 : 0x1305)
#define RTL8365MB_DIGITAL_INTERFACE_SELECT_MODE_OFFSET(id) ((id) == 1 ? 4 : 0)
#define RTL8365MB_DIGITAL_INTERFACE_SELECT_MODE_MASK(id) (0xf << RTL8365MB_DIGITAL_INTERFACE_SELECT_MODE_OFFSET(id))

struct regmap { unsigned int regs[65536], sds[2048], addr; };
struct rtl8365mb_extint { int id; };
struct chip_info { int chip_ver; };
struct rtl8365mb { struct chip_info *chip_info; };
struct realtek_priv { struct regmap *map, *map_nolock; struct rtl8365mb *chip_data; int map_lock; };
static struct rtl8365mb_extint extint = { 1 };
static const struct rtl8365mb_extint *rtl8365mb_get_port_extint(struct realtek_priv *p, int port) { return &extint; }
static int rtl8365mb_ext_init_sgmii_fw(struct realtek_priv *p) { return 0; }
static int calls, fail_at, data_writes, command_reads, busy_reads, locked;
static void rtl83xx_lock(struct realtek_priv *p) { assert(!locked); locked = 1; }
static void rtl83xx_unlock(struct realtek_priv *p) { assert(locked); locked = 0; }

static int regmap_write(struct regmap *m, unsigned int reg, unsigned int val)
{
    if (reg >= 0x6600 && reg <= 0x6602) assert(locked);
    if (++calls == fail_at) return -EIO;
    m->regs[reg] = val;
    if (reg == 0x6601) m->addr = val;
    if (reg == 0x6602) data_writes++;
    if (reg == 0x6600) {
        if (val == 0xc0) m->sds[m->addr] = m->regs[0x6602];
        if (val == 0x80) m->regs[0x6602] = m->sds[m->addr];
    }
    return 0;
}

static int regmap_read(struct regmap *m, unsigned int reg, unsigned int *val)
{
    if (reg >= 0x6600 && reg <= 0x6602) assert(locked);
    if (++calls == fail_at) return -EIO;
    if (reg == 0x6600) {
        command_reads++;
        if (busy_reads) { busy_reads--; *val = 0x100; return 0; }
    }
    *val = m->regs[reg];
    return 0;
}

static int regmap_update_bits(struct regmap *m, unsigned int reg, unsigned int mask, unsigned int val)
{
    if (++calls == fail_at) return -EIO;
    m->regs[reg] = (m->regs[reg] & ~mask) | (val & mask);
    return 0;
}

/* Bound the mock poll; kernel timing remains the real regmap macro's responsibility. */
#define regmap_read_poll_timeout(map, reg, val, cond, sleep_us, timeout_us) ({ \
    int poll_ret = 0, attempts = 0; \
    do { poll_ret = regmap_read(map, reg, &(val)); \
         if (poll_ret || (cond)) break; \
         if (++attempts == 100) { poll_ret = -ETIMEDOUT; break; } \
    } while (1); poll_ret; })

/* PATCH_CODE */

int main(int argc, char **argv)
{
    struct regmap map = {0};
    struct chip_info chip = {0xa0};
    struct rtl8365mb mb = {&chip};
    struct realtek_priv priv = {&map, &map, &mb, 0};
    unsigned int val;
    assert(argc == 2);
    if (!strcmp(argv[1], "extint")) {
        assert(rtl8365mb_ext_init_sgmii(&priv, 6, PHY_INTERFACE_MODE_SGMII) == 0);
        assert(map.regs[0x1305] == 0x90);
        assert(map.regs[0x13c3] == 0);
    } else if (!strcmp(argv[1], "read")) {
        map.sds[2] = 0x5a5a; val = 0xbeef; busy_reads = 2;
        assert(rtl8365mb_sds_indacs_read(&priv, 2, &val) == 0);
        assert(val == 0x5a5a && map.sds[2] == 0x5a5a);
        assert(!data_writes && command_reads == 4);
    } else if (!strcmp(argv[1], "read-errors")) {
        for (fail_at = 1; fail_at <= 5; fail_at++) {
            calls = 0; val = 0xbeef;
            assert(rtl8365mb_sds_indacs_read(&priv, 2, &val) == -EIO);
            assert(val == 0xbeef && !locked);
        }
    } else if (!strcmp(argv[1], "write-errors")) {
        for (fail_at = 1; fail_at <= 5; fail_at++) {
            calls = 0;
            assert(rtl8365mb_sds_indacs_write(&priv, 2, 0xabcd) == -EIO);
            assert(!locked);
        }
    } else if (!strcmp(argv[1], "timeout")) {
        busy_reads = 100; val = 0xbeef;
        assert(rtl8365mb_sds_indacs_read(&priv, 2, &val) == -ETIMEDOUT);
        assert(val == 0xbeef && !data_writes && !locked);
        busy_reads = 100;
        assert(rtl8365mb_sds_indacs_write(&priv, 2, 0xabcd) == -ETIMEDOUT);
        assert(!data_writes && !locked);
    } else if (!strcmp(argv[1], "nway-error")) {
        fail_at = 1;
        assert(rtl8365mb_ext_sgmii_nway(&priv, false) == -EIO);
        assert(calls == 1 && !data_writes);
    } else if (!strcmp(argv[1], "nway")) {
        map.sds[2] = 0xa65a;
        assert(rtl8365mb_ext_sgmii_nway(&priv, false) == 0);
        assert(map.sds[2] == ((0xa65a & ~0x200) | 0x100));
        assert(rtl8365mb_ext_sgmii_nway(&priv, true) == 0);
        assert(map.sds[2] == (0xa65a | 0x300));
    } else { assert(0); }
    assert(!locked);
    return 0;
}
