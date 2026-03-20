#ifndef LLAMA_H
#define LLAMA_H
#include <stdint.h>
typedef struct llama_model llama_model;
typedef struct llama_context llama_context;
#ifdef __cplusplus
extern "C" {
#endif
void llama_backend_init(void);
void llama_backend_free(void);
#ifdef __cplusplus
}
#endif
#endif
