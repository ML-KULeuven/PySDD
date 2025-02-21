

#ifndef FNF_H_
#define FNF_H_

int is_cnf(Fnf* fnf);
int is_dnf(Fnf* fnf);
void free_fnf(Fnf* fnf);
void print_fnf(char* type, FILE* file, const Fnf* fnf);
void print_cnf(FILE* file, const Cnf* cnf);
void print_dnf(FILE* file, const Dnf* dnf);

#endif
