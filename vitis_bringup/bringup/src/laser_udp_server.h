#ifndef LASER_UDP_SERVER_H
#define LASER_UDP_SERVER_H

#ifndef LASER_HAS_LWIP
#if defined(__has_include)
#if __has_include("lwip/init.h") && __has_include("lwip/udp.h") && \
    __has_include("netif/xadapter.h")
#define LASER_HAS_LWIP 1
#else
#define LASER_HAS_LWIP 0
#endif
#else
#define LASER_HAS_LWIP 0
#endif
#endif

#ifndef LASER_UDP_DEBUG
#define LASER_UDP_DEBUG 1
#endif

int laser_udp_server_run(void);

#endif
