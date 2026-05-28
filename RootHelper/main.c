#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/_types/_pid_t.h>
#include <sys/resource.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <limits.h>
#include <libproc.h>

static const char *TARGET_PATH = "/opt/procursus/etc/apt/sources.list.d/procursus.sources";
static const char *DPKG_PATH = "/opt/procursus/bin/dpkg";

int is_url_safe(const char *url) {
    if (!url) return 0;
    return (strncmp(url, "http://", 7) == 0) || (strncmp(url, "https://", 8) == 0);
}

int main(int argc, char *argv[]) {
    if (geteuid() != 0) {
        fprintf(stderr, "RootHelper: must be ran as root.\n");
        return 2;
    }

    pid_t ppid = getppid();
    char parentpath[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(ppid, parentpath, sizeof(parentpath)) <= 0) {
        fprintf(stderr, "RootHelper: cannot verify caller\n");
        return 2;
    }
    if (strcmp(parentpath, "/Applications/Mochi.app/Contents/MacOS/Mochi") != 0) {
        fprintf(stderr, "RootHelper: unauthorized caller\n");
        return 2;
    }
    
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <repository-url>\n", argv[0]);
        return 1;
    }
    
    if (strcmp(argv[1], "install") == 0) {
        if (argc < 3) {
            fprintf(stderr, "Usage: %s install <path-to-deb>\n", argv[0]);
            return 1;
        }
        const char *debpath = argv[2];
        if (debpath[0] != '/') {
            fprintf(stderr, "RootHelper: deb path must be absolute\n");
            return 3;
        }
        struct stat st;
        if (stat(debpath, &st) != 0) {
            fprintf(stderr, "RootHelper: deb file not found: %s\n", debpath);
            return 4;
        }
        execl(DPKG_PATH, "dpkg", "-i", debpath, (char *)NULL);
        fprintf(stderr, "RootHelper: failed to exec dpkg: %s\n", strerror(errno));
        return 7;
    }

    const char *url = argv[1];
    if (!is_url_safe(url)) {
        fprintf(stderr, "RootHelper: invalid url\n");
        return 3;
    }

    char dirbuf[PATH_MAX];
    strncpy(dirbuf, TARGET_PATH, sizeof(dirbuf));
    char *p = strrchr(dirbuf, '/');
    if (p) *p = '\0';
    if (mkdir(dirbuf, 0755) != 0) {
        if (errno != EEXIST) {
            fprintf(stderr, "RootHelper: mkdir failed: %s\n", strerror(errno));
            return 4;
        }
    }

    char entry[4096];
    int n = snprintf(entry, sizeof(entry), "Types: deb\nURIs: %s\nSuites: ./\nComponents: main\n\n", url);
    if (n <= 0 || n >= (int)sizeof(entry)) {
        fprintf(stderr, "RootHelper: url too long\n");
        return 5;
    }
    FILE *f = fopen(TARGET_PATH, "a+");
    if (!f) {
        fprintf(stderr, "RootHelper: cannot open %s: %s\n", TARGET_PATH, strerror(errno));
        return 6;
    }
    if (fseek(f, 0, SEEK_END) == 0) {
        long sz = ftell(f);
        if (sz > 0) {
            int need_prefix = 0;
            char last = 0;
            char second_last = 0;
            if (sz >= 1) {
                if (fseek(f, -1, SEEK_END) == 0) {
                    if (fread(&last, 1, 1, f) != 1) last = 0;
                }
            }
            if (sz >= 2) {
                if (fseek(f, -2, SEEK_END) == 0) {
                    if (fread(&second_last, 1, 1, f) != 1) second_last = 0;
                }
            }

            if (last == '\n' && second_last == '\n') {
                need_prefix = 0;
            } else if (last == '\n') {
                need_prefix = 1;
            } else {
                need_prefix = 2;
            }

            if (need_prefix == 1) {
                if (fwrite("\n", 1, 1, f) != 1) {
                    fprintf(stderr, "RootHelper: write failed: %s\n", strerror(errno));
                    fclose(f);
                    return 7;
                }
            } else if (need_prefix == 2) {
                if (fwrite("\n\n", 1, 2, f) != 2) {
                    fprintf(stderr, "RootHelper: write failed: %s\n", strerror(errno));
                    fclose(f);
                    return 7;
                }
            }
        }
    }

    if (fwrite(entry, 1, (size_t)n, f) != (size_t)n) {
        fprintf(stderr, "RootHelper: write failed: %s\n", strerror(errno));
        fclose(f);
        return 7;
    }

    fclose(f);
    printf("OK\n");
    return 0;
}
