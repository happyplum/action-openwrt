#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef uint16_t u16;
typedef uint32_t u32;
#define GENMASK(high, low) (((1U << ((high) - (low) + 1)) - 1) << (low))
#define FIELD_PREP(mask, val) (((u32)(val) << __builtin_ctz(mask)) & (mask))
#define FIELD_GET(mask, val) (((u32)(val) & (mask)) >> __builtin_ctz(mask))
#define FIELD_FIT(mask, val) (!((u32)(val) & ~((mask) >> __builtin_ctz(mask))))

struct mutex { bool held; };
struct regmap {
    const u32 *pre, *post;
    size_t pre_len, post_len, pre_pos, post_pos;
    u32 last_status;
    int commands, bulk_reads;
};
struct rtl8365mb { struct mutex table_lock; };
struct realtek_priv { struct regmap *map; struct rtl8365mb *chip_data; };
static struct mutex *table_lock;
static const u16 table_data[] = {0x005a, 0x1234, 0x0003};

static void mutex_lock(struct mutex *lock) { assert(!lock->held); lock->held = true; }
static void mutex_unlock(struct mutex *lock) { assert(lock->held); lock->held = false; }

static int regmap_read(struct regmap *map, unsigned int reg, u32 *val)
{
    assert(table_lock->held && reg == 0x0502);
    const u32 *sequence = map->commands ? map->post : map->pre;
    size_t count = map->commands ? map->post_len : map->pre_len;
    size_t *position = map->commands ? &map->post_pos : &map->pre_pos;
    *val = sequence[*position < count ? *position : count - 1];
    (*position)++;
    map->last_status = *val;
    return 0;
}

static int regmap_write(struct regmap *map, unsigned int reg, unsigned int val)
{
    assert(table_lock->held && reg == 0x0501 && val == 0);
    assert(!(map->last_status & 0x2000));
    return 0;
}

static int regmap_update_bits(struct regmap *map, unsigned int reg,
                              unsigned int mask, unsigned int val)
{
    assert(table_lock->held && reg == 0x0500);
    map->commands++;
    return 0;
}

static int regmap_bulk_read(struct regmap *map, unsigned int reg, u16 *val, size_t count)
{
    assert(table_lock->held && reg == 0x0520 && count == 3);
    assert(!(map->last_status & 0x2000));
    memcpy(val, table_data, sizeof(table_data));
    map->bulk_reads++;
    return 0;
}

static int regmap_bulk_write(struct regmap *map, unsigned int reg,
                             const u16 *val, size_t count)
{
    assert(0 && "read transaction must not write table data");
    return -EIO;
}

/* Only bound the mock attempts; the kernel macro owns hardware timing. */
#define regmap_read_poll_timeout(map, reg, val, cond, sleep_us, timeout_us) ({ \
    int poll_ret = 0, attempts = 0; \
    do { poll_ret = regmap_read(map, reg, &(val)); \
         if (poll_ret || (cond)) break; \
         if (++attempts == 100) { poll_ret = -ETIMEDOUT; break; } \
    } while (1); poll_ret; })

/* PATCH_CODE */

int main(int argc, char **argv)
{
    const u32 ready[] = {0}, busy_then_ready[] = {0x2000, 0x2000, 0};
    const u32 idle_low_bit[] = {1}, busy[] = {0x2000};
    struct regmap map = {.pre = ready, .post = ready, .pre_len = 1, .post_len = 1};
    struct rtl8365mb mb = {0};
    struct realtek_priv priv = {&map, &mb};
    const u16 unchanged[] = {0xbeef, 0xbeef, 0xbeef};
    u16 result[] = {0xbeef, 0xbeef, 0xbeef};
    int expected = 0;
    assert(argc == 2);
    table_lock = &mb.table_lock;
    if (!strcmp(argv[1], "pre-busy")) {
        map.pre = busy_then_ready; map.pre_len = 3;
    } else if (!strcmp(argv[1], "post-busy")) {
        map.post = busy_then_ready; map.post_len = 3;
    } else if (!strcmp(argv[1], "pre-idle-low-bit")) {
        map.pre = idle_low_bit;
    } else if (!strcmp(argv[1], "post-idle-low-bit")) {
        map.post = idle_low_bit;
    } else if (!strcmp(argv[1], "pre-timeout")) {
        map.pre = busy; expected = -ETIMEDOUT;
    } else if (!strcmp(argv[1], "post-timeout")) {
        map.post = busy; expected = -ETIMEDOUT;
    } else { assert(0); }
    assert(rtl8365mb_table_access(&priv, RTL8365MB_TABLE_CVLAN,
                                RTL8365MB_TABLE_READ, 0, result) == expected);
    assert(!table_lock->held);
    if (expected) {
        assert(!map.bulk_reads && !memcmp(result, unchanged, sizeof(result)));
        assert(map.commands == (!strcmp(argv[1], "post-timeout") ? 1 : 0));
    } else {
        assert(map.commands == 1 && map.bulk_reads == 1);
        assert(!memcmp(result, table_data, sizeof(result)));
    }
    return 0;
}
