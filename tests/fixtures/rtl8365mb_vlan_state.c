#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef uint16_t u16;
typedef uint32_t u32;
#define BIT(n) (1U << (n))
#define GENMASK(h,l) (((1U << ((h)-(l)+1))-1) << (l))
#define FIELD_PREP(m,v) (((u32)(v) << __builtin_ctz(m)) & (m))
#define FIELD_GET(m,v) (((u32)(v) & (m)) >> __builtin_ctz(m))
#define FIELD_MAX(m) ((m) >> __builtin_ctz(m))
#define FIELD_WIDTH(m) __builtin_popcount(m)
#define BRIDGE_VLAN_INFO_PVID 2
#define BRIDGE_VLAN_INFO_UNTAGGED 4
#define RTL8365MB_PORT_ISOLATION_REG(p) (0x08a2 + (p))
#define dev_dbg(...) ((void)0)
static int logs;
#define dev_err(...) (logs++)
#define NL_SET_ERR_MSG_MOD(...) ((void)0)
#define NL_SET_ERR_MSG_FMT_MOD(...) ((void)0)
struct netlink_ext_ack { int unused; };
struct switchdev_obj_port_vlan { u16 vid, flags; };
struct rtl8366_vlan_4k { u16 member, untag, fid; };
struct rtl8366_vlan_mc { u16 member, fid, priority, vid; };
enum io_op { READ, UPDATE, MC_READ, MC_WRITE, TABLE_READ, TABLE_WRITE };
struct regmap {
    u32 regs[0x1000]; u16 table[4096][3];
    int table_error, mc_error, table_calls, mc_calls, fail_reg, failed;
    int inject, op, reg, nth, seen, after_write, rollback_error;
};
static int io_error(struct regmap *m, int op, int reg) {
    if (!m->inject || m->op!=op || (m->reg>=0 && m->reg!=reg)) return 0;
    if (++m->seen==m->nth) return -EIO;
    return m->seen>m->nth ? m->rollback_error : 0;
}
struct realtek_priv { struct regmap *map; void *dev; };
struct dsa_port { int index, bridge; };
struct dsa_bridge { int num; };
struct dsa_switch { struct realtek_priv *priv; struct dsa_port ports[4]; int num_ports; };
#define RTL8365MB_MAX_NUM_PORTS 11
#define dsa_switch_for_each_available_port(dp,ds) \
    for (int i=0; i<(ds)->num_ports && ((dp)=&(ds)->ports[i],1); i++)
static bool dsa_port_offloads_bridge(struct dsa_port *dp, struct dsa_bridge *br) { return dp->bridge == br->num; }
static u32 dsa_cpu_ports(struct dsa_switch *ds) { return BIT(2); }
static int regmap_read(struct regmap *m, unsigned reg, u32 *v) {
    int ret=io_error(m,READ,reg); if (ret) return ret;
    *v=m->regs[reg]; return 0;
}
static int regmap_update_bits(struct regmap *m, unsigned reg, u32 mask, u32 val) {
    if (m->fail_reg == reg) { m->failed++; return -EIO; }
    int ret=io_error(m,UPDATE,reg); if (ret && !m->after_write) return ret;
    m->regs[reg]=(m->regs[reg]&~mask)|(val&mask); return ret;
}
static int regmap_bulk_read(struct regmap *m, unsigned reg, void *v, size_t n) {
    m->mc_calls++;
    if (m->mc_error) return m->mc_error;
    int ret=io_error(m,MC_READ,reg); if (ret) return ret;
    for (size_t i=0;i<n;i++) ((u16 *)v)[i]=m->regs[reg+i];
    return 0;
}
static int regmap_bulk_write(struct regmap *m, unsigned reg, const void *v, size_t n) {
    int ret=io_error(m,MC_WRITE,reg); if (ret && !m->after_write) return ret;
    for (size_t i=0;i<n;i++) m->regs[reg+i]=((const u16 *)v)[i];
    return ret;
}
/* The table transaction itself is covered by test_rtl8365mb_vlan.py. */
static int rtl8365mb_table_access(struct realtek_priv *p, int table, int op, u16 vid, u16 *buf) {
    struct regmap *m=p->map; m->table_calls++;
    if (m->table_error) return m->table_error;
    int ret=io_error(m,op ? TABLE_WRITE : TABLE_READ,vid);
    if (ret && (!op || !m->after_write)) return ret;
    if (op) memcpy(m->table[vid],buf,6); else memcpy(buf,m->table[vid],6);
    return ret;
}
#define RTL8365MB_TABLE_CVLAN 3
#define RTL8365MB_TABLE_READ 0
#define RTL8365MB_TABLE_WRITE 1
/* PATCH_CODE */

int main(int argc, char **argv) {
    struct regmap m={0};
    struct realtek_priv p={.map=&m};
    struct dsa_switch ds={.priv=&p,.ports={{0,1},{1,1},{2,0},{3,1}},.num_ports=3};
    struct dsa_bridge br={1};
    struct switchdev_obj_port_vlan v={10,BRIDGE_VLAN_INFO_PVID|BRIDGE_VLAN_INFO_UNTAGGED};
    assert(argc==2);
    const char *c=argv[1];
    int port=!strcmp(c,"delete-odd") ? 1 : 0;
    /* Two nonzero PVID fields and undefined upper bits in both bytes. */
    m.regs[0x700]=0xe3e1;
    m.regs[RTL8365MB_VLAN_MC_CONF_REG(1)]=BIT(0)|BIT(1)|BIT(2);
    m.regs[RTL8365MB_VLAN_MC_CONF_REG(1)+3]=10;
    m.regs[RTL8365MB_VLAN_MC_CONF_REG(3)]=BIT(1)|BIT(2);
    m.regs[RTL8365MB_VLAN_MC_CONF_REG(3)+3]=20;
    m.regs[0x7aa]=0x30; /* Neighboring port 2 accepts only untagged. */
    if (!strncmp(c,"join-",5)) {
        ds.num_ports=4;
        for (int i=0;i<4;i++) m.regs[RTL8365MB_PORT_ISOLATION_REG(i)]=0x8044|BIT(i);
        u32 before[0x1000]; memcpy(before,m.regs,sizeof(before));
        m.inject=1; m.reg=-1; m.nth=1; m.op=UPDATE;
        if (strstr(c,"middle")) m.nth=2;
        if (strstr(c,"self")) m.nth=3;
        if (strstr(c,"read")) { m.op=READ; m.nth=2; }
        m.after_write=strstr(c,"applied")!=NULL;
        if (strstr(c,"rollback")) m.rollback_error=-ETIMEDOUT;
        bool offload=false;
        assert(rtl8365mb_port_bridge_join(&ds,0,br,&offload,NULL)==-EIO);
        if (m.rollback_error) assert(logs>0);
        else assert(!memcmp(before,m.regs,sizeof(before)));
        return 0;
    }
    if (!strcmp(c,"mixed-format")) {
        memset(m.regs,0,sizeof(m.regs));
        for (int i=0;i<40;i++) {
            v.vid=10+i; v.flags=BRIDGE_VLAN_INFO_UNTAGGED;
            assert(!rtl8365mb_vlan_add(&ds,0,&v,NULL));
            v.flags=BRIDGE_VLAN_INFO_PVID;
            assert(!rtl8365mb_vlan_add(&ds,1,&v,NULL));
            assert(m.regs[RTL8365MB_VLAN_MC_CONF_REG(1)]==(BIT(0)|BIT(1)));
            assert(!rtl8365mb_vlan_del(&ds,0,&v));
            assert(!rtl8365mb_vlan_del(&ds,1,&v));
            for (int slot=1;slot<32;slot++)
                for (int word=0;word<4;word++) assert(!m.regs[RTL8365MB_VLAN_MC_CONF_REG(slot)+word]);
        }
        return 0;
    }
    if (!strncmp(c,"add-",4)) {
        bool existing=strstr(c,"existing")!=NULL;
        v.vid=existing ? 10 : 30;
        m.regs[0x700]=0xe3e3; /* Force a PVID change, preserve other fields. */
        m.regs[0x7aa]=0x31;
        m.table[v.vid][0]=BIT(1)|(BIT(1)<<8);
        m.table[v.vid][1]=0x4321; m.table[v.vid][2]=0xabc0;
        m.regs[RTL8365MB_VLAN_MC_CONF_REG(1)+1]=0xa5a5;
        m.regs[RTL8365MB_VLAN_MC_CONF_REG(1)+2]=0x5a5a;
        /* Empty VID slots may still contain unrelated hardware fields. */
        m.regs[RTL8365MB_VLAN_MC_CONF_REG(2)]=0x8800;
        m.regs[RTL8365MB_VLAN_MC_CONF_REG(2)+1]=0x4567;
        if (strstr(c,"revoke")) { v.flags=0; m.regs[0x700]=0xe3e1; m.regs[0x7aa]=0x30; }
        struct regmap before=m;
        m.inject=1; m.reg=-1; m.nth=1;
        if (strstr(c,"mc-read")) m.op=MC_READ;
        else if (strstr(c,"mc-write")) m.op=MC_WRITE;
        else if (strstr(c,"pvid-read")) { m.op=READ; m.reg=0x700; }
        else if (strstr(c,"frame-read")) { m.op=READ; m.reg=0x7aa; }
        else if (strstr(c,"pvid-write")) { m.op=UPDATE; m.reg=0x700; }
        else if (strstr(c,"frame-write")) { m.op=UPDATE; m.reg=0x7aa; }
        else if (strstr(c,"4k-read")) m.op=TABLE_READ;
        else m.op=TABLE_WRITE;
        m.after_write=strstr(c,"applied")!=NULL;
        if (strstr(c,"rollback")) m.rollback_error=-ETIMEDOUT;
        assert(rtl8365mb_vlan_add(&ds,0,&v,NULL)==-EIO);
        if (m.rollback_error) assert(logs>0);
        else {
            assert(!memcmp(before.regs,m.regs,sizeof(m.regs)));
            assert(!memcmp(before.table,m.table,sizeof(m.table)));
        }
        return 0;
    }
    if (!strncmp(c,"errno-",6)) {
        m.table_error=(!strcmp(c,"errno-first")||!strcmp(c,"errno-both")) ? -EIO : 0;
        m.mc_error=(!strcmp(c,"errno-second")||!strcmp(c,"errno-both")) ? -ETIMEDOUT : 0;
        int expected=m.table_error ? m.table_error : m.mc_error;
        assert(rtl8365mb_vlan_del(&ds,0,&v)==expected);
        assert(m.table_calls && m.mc_calls); return 0;
    }
    if (!strncmp(c,"delete-",7)) {
        if (port) m.regs[0x700]=0xe1e3;
        u32 before=m.regs[0x700];
        assert(!rtl8365mb_vlan_del(&ds,port,&v));
        assert(((m.regs[0x7aa]>>(port*2))&3)==RTL8365MB_FRAME_TYPE_TAGGED_ONLY);
        assert(m.regs[0x700]==before);
    } else if (!strcmp(c,"write-pvid")) {
        m.regs[0x700]=0xe3e2;
        assert(!rtl8365mb_vlan_add(&ds,0,&v,NULL));
        assert(m.regs[0x700]==0xe3e1);
    } else if (!strcmp(c,"revoke-pvid") || !strcmp(c,"noncurrent")) {
        v.flags=BRIDGE_VLAN_INFO_UNTAGGED;
        if (!strcmp(c,"noncurrent")) v.vid=20;
        assert(!rtl8365mb_vlan_add(&ds,0,&v,NULL));
        assert((m.regs[0x7aa]&3)==(!strcmp(c,"noncurrent") ? 0 : 1));
        assert(m.table[v.vid][0]&BIT(0));
        assert(m.table[v.vid][0]&(BIT(0)<<8));
        assert(m.regs[0x700]==0xe3e1);
    } else {
        bool offload=false;
        if (!strncmp(c,"leave-",6)) {
            ds.ports[1].bridge=0;
            m.regs[RTL8365MB_VLAN_MC_CONF_REG(1)]=BIT(0)|BIT(2);
        }
        m.regs[RTL8365MB_PORT_ISOLATION_REG(0)]=BIT(2);
        m.regs[RTL8365MB_PORT_ISOLATION_REG(1)]=BIT(2);
        m.regs[RTL8365MB_PORT_ISOLATION_REG(2)]=BIT(0)|BIT(1);
        assert(!rtl8365mb_port_bridge_join(&ds,0,br,&offload,NULL));
        assert(!rtl8365mb_vlan_filtering(&ds,0,strcmp(c,"leave-unaware")!=0,NULL));
        assert(!rtl8365mb_vlan_add(&ds,0,&v,NULL));
        assert(!rtl8365mb_vlan_del(&ds,0,&v));
        /* Model DSA completing unoffload before its bridge_leave callback. */
        ds.ports[0].bridge=0;
        if (!strcmp(c,"fail-isolation")) m.fail_reg=RTL8365MB_PORT_ISOLATION_REG(0);
        if (!strcmp(c,"fail-peer-isolation")) m.fail_reg=RTL8365MB_PORT_ISOLATION_REG(1);
        if (!strcmp(c,"fail-pvid")) m.fail_reg=0x700;
        if (!strcmp(c,"fail-frame")) m.fail_reg=0x7aa;
        rtl8365mb_port_bridge_leave(&ds,0,br);
        if (m.fail_reg) {
            assert(m.failed==1 && logs==1);
            assert((m.regs[0x7aa]&3)==RTL8365MB_FRAME_TYPE_TAGGED_ONLY);
            assert((m.regs[0x700]&31)==(!strcmp(c,"fail-frame") ? 0 : 1));
        } else {
            assert(m.regs[0x700]==0xe3e0);
            assert((m.regs[0x7aa]&3)==RTL8365MB_FRAME_TYPE_ANY_FRAME);
            assert(m.regs[RTL8365MB_PORT_ISOLATION_REG(0)]==BIT(2));
        }
        assert(m.regs[RTL8365MB_PORT_ISOLATION_REG(1)]==
               (BIT(2)|(!strcmp(c,"fail-peer-isolation") ? BIT(0) : 0)));
        assert(m.regs[RTL8365MB_PORT_ISOLATION_REG(2)]==(BIT(0)|BIT(1)));
        assert(m.regs[RTL8365MB_VLAN_MC_CONF_REG(3)]==(BIT(1)|BIT(2)));
        assert(m.regs[RTL8365MB_VLAN_MC_CONF_REG(3)+3]==20);
    }
    assert(m.regs[0x7aa]==(port==1 ? 0x34 : (0x30|(m.regs[0x7aa]&3))));
    return 0;
}
