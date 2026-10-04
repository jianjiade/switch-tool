#include "SMCBridge.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach_time.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sys/time.h>
typedef struct { char major,minor,build,reserved; uint16_t release; } Version;
typedef struct { uint16_t version,length; uint32_t cpu,gpu,mem; } Limit;
typedef struct { uint32_t size,type; char attributes; } Info;
typedef struct { uint32_t key; Version version; Limit limit; Info info; char result,status,command; uint32_t index; uint8_t bytes[32]; } Data;
_Static_assert(sizeof(Data)==80,"SMC ABI mismatch");
static io_connect_t connection;
static const char *socket_path="/var/run/dev.switchtool.socket";
int st_smc_open(void) {
    if(connection) return 0;
    io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"));
    if(!service) return -1;
    int rc=IOServiceOpen(service,mach_task_self(),0,&connection);
    IOObjectRelease(service); return rc;
}
static int call(Data *in,Data *out) {
    size_t size=sizeof(*out); memset(out,0,size);
    int rc=IOConnectCallStructMethod(connection,2,in,sizeof(*in),out,&size);
    return rc ? rc : (out->result ? 1000+(unsigned char)out->result : 0);
}
static int metadata(const char *key,Data *in) {
    if(strlen(key)!=4 || !connection) return -1;
    memset(in,0,sizeof(*in));
    for(int i=0;i<4;i++) in->key=(in->key<<8)|(uint8_t)key[i];
    in->command=9; Data out; int rc=call(in,&out);
    if(rc) return rc;
    if(out.info.size!=1) return -2;
    in->info=out.info; return 0;
}
int st_smc_read(const char *key,uint8_t *value) {
    Data in,out; int rc=metadata(key,&in); if(rc) return rc;
    in.command=5; rc=call(&in,&out); if(!rc) *value=out.bytes[0]; return rc;
}
int st_smc_write(const char *key,uint8_t value) {
    Data in,out; int rc=metadata(key,&in); if(rc) return rc;
    in.command=6; in.bytes[0]=value; return call(&in,&out);
}
void st_smc_close(void) { if(connection) IOServiceClose(connection); connection=0; }
double st_awake_time(void) {
    mach_timebase_info_data_t info; mach_timebase_info(&info);
    return (double)mach_absolute_time()*info.numer/info.denom/1e9;
}
static int socket_fd(void) {
    int fd=socket(AF_UNIX,SOCK_STREAM,0); if(fd<0) return -1;
    struct timeval timeout={2,0};
    setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
    int one=1; setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));
    return fd;
}
static struct sockaddr_un address(void) {
    struct sockaddr_un addr={0}; addr.sun_family=AF_UNIX;
    strlcpy(addr.sun_path,socket_path,sizeof(addr.sun_path)); addr.sun_len=sizeof(addr); return addr;
}
int st_listen(void) {
    int fd=socket_fd(); if(fd<0) return -1;
    unlink(socket_path); struct sockaddr_un addr=address();
    if(bind(fd,(struct sockaddr*)&addr,sizeof(addr)) || chmod(socket_path,0666) || listen(fd,8)) { close(fd); return -1; }
    return fd;
}
int st_connect(void) {
    int fd=socket_fd(); if(fd<0) return -1; struct sockaddr_un addr=address();
    if(connect(fd,(struct sockaddr*)&addr,sizeof(addr))) { close(fd); return -1; } return fd;
}
int st_peer(int fd,unsigned *uid,int *pid) {
    uid_t user; gid_t group; if(getpeereid(fd,&user,&group)) return -1;
    socklen_t size=sizeof(*pid);
    if(getsockopt(fd,SOL_LOCAL,LOCAL_PEERPID,pid,&size)) return -1;
    *uid=user; return 0;
}
