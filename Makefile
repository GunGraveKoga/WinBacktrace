project_dir := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
current_dir := $(notdir $(patsubst %/,%,$(dir $(project_dir))))
build_dir=$(project_dir)build

WINBACKTRACE_SOURCES = WinBacktrace.m DrMinGWModule.m DynamoRIOModule.m \
					   OFException+WinBacktrace.m WinCRTException.m objc_demangle.m

WINBACKTRACE_OBJS = WinBacktrace.plugin.o DrMinGWModule.plugin.o DynamoRIOModule.plugin.o \
					   OFException+WinBacktrace.plugin.o WinCRTException.plugin.o objc_demangle.plugin.o

WINBACKTRACE_OBJS_LIST := $(addprefix $(build_dir)/,$(WINBACKTRACE_OBJS))

WINBACKTRACE_PUBLIC_HEADERS = DrMinGWModule.h  DynamoRIOModule.h  OFException+WinBacktrace.h \
								 WinBacktrace.h  WinCRTException.h  macros.h \
								 dynamorio_types.h				 			  

CC=i686-w64-mingw32-objfw-compile
CHDIR=cd
MKDIR=mkdir
MOVE=mv
COPY=cp
DELETE=rm -rf
AR=ar

WINBACKTRACE=WinBacktrace

SHARED_LIBRARY_EXTANSION=.dll

WINBACKTRACE_PLUGIN=$(WINBACKTRACE)$(SHARED_LIBRARY_EXTANSION)

bindir = bin

includedir = include

.SILENT:

.PHONY: all clean install

all: $(build_dir)/$(WINBACKTRACE_PLUGIN)

$(build_dir)/$(WINBACKTRACE_PLUGIN): $(WINBACKTRACE)

$(WINBACKTRACE): $(WINBACKTRACE_OBJS_LIST)

$(WINBACKTRACE_OBJS_LIST): $(WINBACKTRACE_SOURCES)
	echo -e "\e[1;34mBuilding $(WINBACKTRACE_PLUGIN)...\e[0m"
	$(CC) --builddir $(build_dir) $(WINBACKTRACE_SOURCES) -I. -o $(WINBACKTRACE) --plugin && \
	$(MOVE) $(WINBACKTRACE_PLUGIN) $(build_dir)
	echo -e "\e[1;34mDone.\e[0m"

clean:
	$(DELETE) $(build_dir)/*.o
	$(DELETE) $(build_dir)/*.a
	$(DELETE) $(build_dir)/*.dll
	$(DELETE) $(build_dir)/*.exe
	echo -e "\e[1;34mAll clean.\e[0m"

install:
	echo -e "\e[1;34mCreating $(DESTDIR).\e[0m"
	if test -d $(DESTDIR); then \
		echo -e "\e[1;34mExist.\e[0m"; \
	else \
		$(MKDIR) $(DESTDIR); \
	fi
	echo -e "\e[1;34mCreating $(DESTDIR)/$(bindir).\e[0m"
	if test -d $(DESTDIR)/$(bindir); then \
		echo -e "\e[1;34mExist.\e[0m"; \
	else \
		$(MKDIR) $(DESTDIR)/$(bindir); \
	fi
	echo -e "\e[1;34mCreating $(DESTDIR)/$(includedir).\e[0m"
	if test -d $(DESTDIR)/$(includedir); then \
		echo -e "\e[1;34mExist.\e[0m"; \
	else \
		$(MKDIR) $(DESTDIR)/$(includedir); \
	fi
	echo -e "\e[1;34mInstalling $(WINBACKTRACE_PLUGIN)...\e[0m"
	$(COPY) $(build_dir)/$(WINBACKTRACE_PLUGIN) $(DESTDIR)/$(bindir)/
	echo -e "\e[1;34mDone.\e[0m"
	for header in $(WINBACKTRACE_PUBLIC_HEADERS); do \
		echo -e "\e[1;34mInstalling $$header...\e[0m"; \
		$(COPY) $$header $(DESTDIR)/$(includedir)/; \
		echo -e "\e[1;34mDone.\e[0m"; \
	done
