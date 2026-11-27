/* mlxf_libc_lstat.c -- the facts lstat gives of a path, read by the C compiler from the platform's own struct stat
   (its layout differs between macOS and glibc), for c_file_info in mlxf_libc.f90. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <sys/stat.h>

/* lstat of path, a NUL-terminated name, and the link itself rather than what it names: 0 with the facts, or -1 with
   them untouched. ftype is 1 for a symbolic link, 2 for a regular file, 0 for anything else; perm holds the
   permission bits with set-id and sticky; nlink the hard links (capped at INT32_MAX); uid the owner's 32 bits. */
int mlxf_lstat_facts(const char *path, int32_t *ftype, int32_t *perm, int32_t *nlink, int32_t *uid) {
    struct stat st;
    uintmax_t links;
    if (lstat(path, &st) != 0) return -1;
    *ftype = S_ISLNK(st.st_mode) ? 1 : (S_ISREG(st.st_mode) ? 2 : 0);
    *perm = (int32_t)(st.st_mode & 07777);
    links = st.st_nlink;
    *nlink = links > INT32_MAX ? INT32_MAX : (int32_t)links;
    *uid = (int32_t)st.st_uid;
    return 0;
}
