#include <stdint.h>
int st_smc_open(void);
int st_smc_read(const char *key, uint8_t *value);
int st_smc_write(const char *key, uint8_t value);
void st_smc_close(void);
double st_awake_time(void);
int st_listen(void);
int st_connect(void);
int st_peer(int fd, unsigned *uid, int *pid);
