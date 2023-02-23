FROM alpine AS cupswrapper

RUN apk add gcc make musl-dev
RUN mkdir -p /usr/local/src && cd /usr/local/src && \
        wget https://download.brother.com/welcome/dlf100408/mfc9140cdn_cupswrapper_GPL_source_1.1.4-0.tar.gz && \
        tar xzf mfc9140cdn_cupswrapper_GPL_source_1.1.4-0.tar.gz
RUN cd /usr/local/src/mfc9140cdn_cupswrapper_GPL_source_1.1.4-0/brcupsconfig && \
        make


FROM debian:testing AS debiandriver

RUN apt-get update && apt-get install -y wget

ENV BROTHER_LPR_VERSION 1.1.2-1
ENV BROTHER_CUPSWRAPPER_VERSION 1.1.4-0

RUN mkdir /var/spool/lpd
RUN dpkg --add-architecture i386 && \
   apt-get update && \
   apt-get install -y libc6:i386 && \
   wget https://download.brother.com/welcome/dlf100405/mfc9140cdnlpr-${BROTHER_LPR_VERSION}.i386.deb && \
   wget https://download.brother.com/welcome/dlf100407/mfc9140cdncupswrapper-${BROTHER_CUPSWRAPPER_VERSION}.i386.deb && \
   dpkg -i --force-all mfc9140cdnlpr-${BROTHER_LPR_VERSION}.i386.deb mfc9140cdncupswrapper-${BROTHER_CUPSWRAPPER_VERSION}.i386.deb && \
   rm -f mfc9140cdnlpr-${BROTHER_LPR_VERSION}.i386.deb mfc9140cdncupswrapper-${BROTHER_CUPSWRAPPER_VERSION}.i386.deb


FROM alpine

RUN apk add cups cups-libs cups-client cups-filters file a2ps && \
	ARCH=$(arch -m) && \
	if [[ "$ARCH" != i386 && "$ARCH" != x86_64 ]]; then \
		apk add qemu-i386; \
	fi

RUN adduser -h /home/print -s /bin/bash -D print && \
        addgroup print lp && \
        addgroup print lpadmin && \
        addgroup root lp && \
        addgroup root lpadmin && \
        echo print:print | chpasswd

# stricly needed for qemu-i386 and Brother binaries
COPY --from=debiandriver /usr/lib/i386-linux-gnu/ld-linux.so.2 /usr/lib/i386-linux-gnu/
COPY --from=debiandriver /usr/lib/i386-linux-gnu/libc.so.6 /usr/lib/i386-linux-gnu/
COPY --from=debiandriver /usr/lib/i386-linux-gnu/libm.so.6 /usr/lib/i386-linux-gnu/
RUN ln -s /usr/lib/i386-linux-gnu/ld-linux.so.2 /lib/ld-linux.so.2

COPY --from=debiandriver /opt/brother/Printers/mfc9140cdn /opt/brother/Printers/mfc9140cdn
COPY --from=debiandriver /usr/bin/brprintconf_mfc9140cdn /usr/bin/
COPY --from=cupswrapper /usr/local/src/mfc9140cdn_cupswrapper_GPL_source_1.1.4-0/brcupsconfig/brcupsconfpt1 /opt/brother/Printers/mfc9140cdn/cupswrapper/

# ensure i386 binaries are run through qemu
RUN ARCH=$(arch -m); \
	if [[ "$ARCH" != i386 && "$ARCH" != x86_64 ]]; then \
		echo -e '#!/bin/sh\nqemu-i386 /usr/bin/brprintconf_mfc9140cdn "$@"' > /usr/local/bin/brprintconf_mfc9140cdn && \
        	chmod 755 /usr/local/bin/brprintconf_mfc9140cdn && \
        	mv /opt/brother/Printers/mfc9140cdn/lpd/brmfc9140cdnfilter /opt/brother/Printers/mfc9140cdn/lpd/brmfc9140cdnfilter.i386 && \
        	echo -e '#!/bin/sh\nqemu-i386 /opt/brother/Printers/mfc9140cdn/lpd/brmfc9140cdnfilter.i386 "$@"' > /opt/brother/Printers/mfc9140cdn/lpd/brmfc9140cdnfilter && \
        	chmod 755 /opt/brother/Printers/mfc9140cdn/lpd/brmfc9140cdnfilter; \
	fi

# from Debian postinst
RUN mkdir /var/spool/lpd
RUN /opt/brother/Printers/mfc9140cdn/inf/setupPrintcapij mfc9140cdn -i
RUN /usr/sbin/cupsd && sleep 2 && /opt/brother/Printers/mfc9140cdn/cupswrapper/cupswrappermfc9140cdn

# Setup environment
WORKDIR /home/print

# Default shell
CMD ["/usr/sbin/cupsd", "-f"]
