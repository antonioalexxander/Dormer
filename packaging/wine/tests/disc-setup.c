// Stand-in for a CD installer: reports the drive it runs from and reads a file that sits next to it.
#include <windows.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    char exe[MAX_PATH], root[4] = "?:\\", data[MAX_PATH], line[128] = "(missing)";
    GetModuleFileNameA(NULL, exe, sizeof exe);
    root[0] = exe[0];
    strcpy(data, exe);
    strcpy(strrchr(data, '\\') + 1, "data\\payload.txt");
    FILE *in = fopen(data, "r");
    if (in) { if (fgets(line, sizeof line, in)) line[strcspn(line, "\r\n")] = 0; fclose(in); }
    FILE *out = fopen("C:\\disc-test.log", "w");
    if (!out) return 2;
    fprintf(out, "exe=%s\ndrivetype=%u\npayload=%s\nzdrive=%u\n", exe, GetDriveTypeA(root), line, GetDriveTypeA("Z:\\"));
    fclose(out);
    return in ? 0 : 1;
}
