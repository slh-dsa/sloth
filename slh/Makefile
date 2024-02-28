#	Makefile
#	Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.	

#	===	This is a PC-target makefile for the core SLH-DSA implementation.
#		No hardware acceleration if used like this -- mainly useful for
#		debug purposes.

XBIN	?=	kat_test
CSRC	=	$(wildcard *.c)
CSRC	+=	../drv/kat_drbg.c
OBJS	= 	$(CSRC:.c=.o)
KATNUM	?=	1

CC 		=	gcc
CFLAGS	+=	-Wall -march=native -Ofast -DNDEBUG
#CFLAGS	+=	-Wall -Wextra -Wshadow -fsanitize=address,undefined -g
CFLAGS	+=	-I. -I../drv -DKATNUM=$(KATNUM)
LDLIBS	+=

$(XBIN):	$(OBJS)
	$(CC) $(LDFLAGS) $(CFLAGS) -o $(XBIN) $(OBJS) $(LDLIBS)

%.o:	%.[cS]
	$(CC) $(CFLAGS) -c $^ -o $@

test:	$(XBIN)
	./$(XBIN)	
	sha256sum *.rsp > t.log
	cat t.log ../kat/kat$(KATNUM)-sha256.txt | sort | uniq -c -w 64
	@echo "NOTE >2<- indicates test vector comparison match, 1 is a failure."
clean:
	$(RM) -rf $(XBIN) $(OBJS) *.rsp *.req *.log

