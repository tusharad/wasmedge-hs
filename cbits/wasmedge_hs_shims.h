// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tushar Adhatrao
// wasmedge-hs: C shim layer for struct-by-value WasmEdge functions
//
// GHC's FFI cannot natively handle C functions that return structs by value
// (WasmEdge_String, WasmEdge_Value, WasmEdge_Result, WasmEdge_ValType,
// WasmEdge_Bytes). These thin wrappers take an output pointer instead,
// making all functions return void with out-params — which GHC handles fine.
//
// Naming convention: hs_WasmEdge_* mirrors WasmEdge_* exactly.

#ifndef WASMEDGE_HS_SHIMS_H
#define WASMEDGE_HS_SHIMS_H

#include "wasmedge/wasmedge.h"
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// =========================================================================
// String shims
// =========================================================================

/// Create a WasmEdge_String from a NULL-terminated C string.
/// out->Buf is owned by WasmEdge; call hs_WasmEdge_StringDelete to free.
void hs_WasmEdge_StringCreateByCString(WasmEdge_String *out, const char *str);

/// Create a WasmEdge_String from a buffer of known length.
/// out->Buf is owned by WasmEdge; call hs_WasmEdge_StringDelete to free.
void hs_WasmEdge_StringCreateByBuffer(WasmEdge_String *out, const char *buf,
                                       uint32_t len);

/// Wrap a buffer as a WasmEdge_String (no copy; caller owns the buffer).
/// Do NOT call hs_WasmEdge_StringDelete on the result.
void hs_WasmEdge_StringWrap(WasmEdge_String *out, const char *buf,
                              uint32_t len);

/// Compare two WasmEdge_String objects for equality.
bool hs_WasmEdge_StringIsEqual(const WasmEdge_String *s1,
                                const WasmEdge_String *s2);

/// Copy the content of a WasmEdge_String into buf (at most len bytes).
uint32_t hs_WasmEdge_StringCopy(const WasmEdge_String *str, char *buf,
                                 uint32_t len);

/// Delete (free) a WasmEdge_String created by hs_WasmEdge_StringCreateBy*.
void hs_WasmEdge_StringDelete(WasmEdge_String *str);

/// Get the length of a WasmEdge_String.
uint32_t hs_WasmEdge_StringGetLength(const WasmEdge_String *str);

/// Get the buffer pointer of a WasmEdge_String (valid as long as str is alive).
const char *hs_WasmEdge_StringGetBuf(const WasmEdge_String *str);

// =========================================================================
// Bytes shims
// =========================================================================

/// Create a WasmEdge_Bytes from a buffer (copies the data).
void hs_WasmEdge_BytesCreate(WasmEdge_Bytes *out, const uint8_t *buf,
                              uint32_t len);

/// Wrap a buffer as WasmEdge_Bytes (no copy; caller owns the buffer).
void hs_WasmEdge_BytesWrap(WasmEdge_Bytes *out, const uint8_t *buf,
                            uint32_t len);

/// Delete a WasmEdge_Bytes created by hs_WasmEdge_BytesCreate.
void hs_WasmEdge_BytesDelete(WasmEdge_Bytes *bytes);

/// Get the length of a WasmEdge_Bytes.
uint32_t hs_WasmEdge_BytesGetLength(const WasmEdge_Bytes *bytes);

/// Get the buffer pointer of a WasmEdge_Bytes.
const uint8_t *hs_WasmEdge_BytesGetBuf(const WasmEdge_Bytes *bytes);

// =========================================================================
// Result shims
// =========================================================================

/// Fill *out with WasmEdge_Result_Success.
void hs_WasmEdge_Result_Success(WasmEdge_Result *out);

/// Fill *out with WasmEdge_Result_Terminate.
void hs_WasmEdge_Result_Terminate(WasmEdge_Result *out);

/// Fill *out with WasmEdge_Result_Fail.
void hs_WasmEdge_Result_Fail(WasmEdge_Result *out);

/// Check whether a result is OK (Success or Terminate).
bool hs_WasmEdge_ResultOK(const WasmEdge_Result *res);

/// Generate a result with a given category and code.
void hs_WasmEdge_ResultGen(WasmEdge_Result *out,
                            enum WasmEdge_ErrCategory category,
                            uint32_t code);

/// Get the 24-bit error code from a result.
uint32_t hs_WasmEdge_ResultGetCode(const WasmEdge_Result *res);

/// Get the error category from a result.
enum WasmEdge_ErrCategory hs_WasmEdge_ResultGetCategory(const WasmEdge_Result *res);

/// Get the error message for a result (static string; do NOT free).
const char *hs_WasmEdge_ResultGetMessage(const WasmEdge_Result *res);

// =========================================================================
// ValType shims
// =========================================================================

void hs_WasmEdge_ValTypeGenI32(WasmEdge_ValType *out);
void hs_WasmEdge_ValTypeGenI64(WasmEdge_ValType *out);
void hs_WasmEdge_ValTypeGenF32(WasmEdge_ValType *out);
void hs_WasmEdge_ValTypeGenF64(WasmEdge_ValType *out);
void hs_WasmEdge_ValTypeGenV128(WasmEdge_ValType *out);
void hs_WasmEdge_ValTypeGenFuncRef(WasmEdge_ValType *out);
void hs_WasmEdge_ValTypeGenExternRef(WasmEdge_ValType *out);

bool hs_WasmEdge_ValTypeIsEqual(const WasmEdge_ValType *t1,
                                 const WasmEdge_ValType *t2);
bool hs_WasmEdge_ValTypeIsI32(const WasmEdge_ValType *t);
bool hs_WasmEdge_ValTypeIsI64(const WasmEdge_ValType *t);
bool hs_WasmEdge_ValTypeIsF32(const WasmEdge_ValType *t);
bool hs_WasmEdge_ValTypeIsF64(const WasmEdge_ValType *t);
bool hs_WasmEdge_ValTypeIsV128(const WasmEdge_ValType *t);
bool hs_WasmEdge_ValTypeIsFuncRef(const WasmEdge_ValType *t);
bool hs_WasmEdge_ValTypeIsExternRef(const WasmEdge_ValType *t);
bool hs_WasmEdge_ValTypeIsRef(const WasmEdge_ValType *t);
bool hs_WasmEdge_ValTypeIsRefNull(const WasmEdge_ValType *t);

// =========================================================================
// Value shims
// =========================================================================

/// WasmEdge_Value is {uint128_t, WasmEdge_ValType}.  We represent
/// uint128_t as two uint64_t words (hi, lo) in little-endian order.

void hs_WasmEdge_ValueGenI32(WasmEdge_Value *out, int32_t val);
void hs_WasmEdge_ValueGenI64(WasmEdge_Value *out, int64_t val);
void hs_WasmEdge_ValueGenF32(WasmEdge_Value *out, float val);
void hs_WasmEdge_ValueGenF64(WasmEdge_Value *out, double val);
void hs_WasmEdge_ValueGenV128(WasmEdge_Value *out, uint64_t hi, uint64_t lo);
void hs_WasmEdge_ValueGenFuncRef(WasmEdge_Value *out,
                                  const WasmEdge_FunctionInstanceContext *cxt);
void hs_WasmEdge_ValueGenExternRef(WasmEdge_Value *out, void *ref);
void hs_WasmEdge_ValueGenNullFuncRef(WasmEdge_Value *out);
void hs_WasmEdge_ValueGenNullExternRef(WasmEdge_Value *out);

int32_t  hs_WasmEdge_ValueGetI32(const WasmEdge_Value *val);
int64_t  hs_WasmEdge_ValueGetI64(const WasmEdge_Value *val);
float    hs_WasmEdge_ValueGetF32(const WasmEdge_Value *val);
double   hs_WasmEdge_ValueGetF64(const WasmEdge_Value *val);

/// Retrieve the V128 as two uint64_t words (written to *hi and *lo).
void hs_WasmEdge_ValueGetV128(const WasmEdge_Value *val, uint64_t *hi,
                               uint64_t *lo);

bool                              hs_WasmEdge_ValueIsNullRef(const WasmEdge_Value *val);
const WasmEdge_FunctionInstanceContext *hs_WasmEdge_ValueGetFuncRef(const WasmEdge_Value *val);
void                             *hs_WasmEdge_ValueGetExternRef(const WasmEdge_Value *val);

/// Get the ValType of a value (written to *out).
void hs_WasmEdge_ValueGetType(const WasmEdge_Value *val, WasmEdge_ValType *out);

// =========================================================================
// Value array helpers (for batch invoke calls)
// =========================================================================

/// Allocate an array of n WasmEdge_Value on the C heap (caller must free).
WasmEdge_Value *hs_WasmEdge_ValueArrayAlloc(uint32_t n);

/// Free an array previously allocated by hs_WasmEdge_ValueArrayAlloc.
void hs_WasmEdge_ValueArrayFree(WasmEdge_Value *arr);

/// Set arr[idx] = val.
void hs_WasmEdge_ValueArraySet(WasmEdge_Value *arr, uint32_t idx,
                                const WasmEdge_Value *val);

/// Get arr[idx] into *out.
void hs_WasmEdge_ValueArrayGet(const WasmEdge_Value *arr, uint32_t idx,
                                WasmEdge_Value *out);

// =========================================================================
// Execution shims — functions that return WasmEdge_Result by value
// =========================================================================

// Loader
void hs_WasmEdge_LoaderParseFromFile(WasmEdge_Result *out,
                                      WasmEdge_LoaderContext *cxt,
                                      WasmEdge_ASTModuleContext **module,
                                      const char *path);

void hs_WasmEdge_LoaderParseFromBytes(WasmEdge_Result *out,
                                       WasmEdge_LoaderContext *cxt,
                                       WasmEdge_ASTModuleContext **module,
                                       const WasmEdge_Bytes *bytes);

void hs_WasmEdge_LoaderSerializeASTModule(WasmEdge_Result *out,
                                           WasmEdge_LoaderContext *cxt,
                                           const WasmEdge_ASTModuleContext *ast,
                                           WasmEdge_Bytes *buf);

// Validator
void hs_WasmEdge_ValidatorValidate(WasmEdge_Result *out,
                                    WasmEdge_ValidatorContext *cxt,
                                    const WasmEdge_ASTModuleContext *module);

// Executor
void hs_WasmEdge_ExecutorInstantiate(WasmEdge_Result *out,
                                      WasmEdge_ExecutorContext *cxt,
                                      WasmEdge_ModuleInstanceContext **mod_inst,
                                      WasmEdge_StoreContext *store,
                                      const WasmEdge_ASTModuleContext *ast);

void hs_WasmEdge_ExecutorRegister(WasmEdge_Result *out,
                                   WasmEdge_ExecutorContext *cxt,
                                   WasmEdge_ModuleInstanceContext **mod_inst,
                                   WasmEdge_StoreContext *store,
                                   const WasmEdge_ASTModuleContext *ast,
                                   const WasmEdge_String *mod_name);

void hs_WasmEdge_ExecutorRegisterImport(WasmEdge_Result *out,
                                         WasmEdge_ExecutorContext *cxt,
                                         WasmEdge_StoreContext *store,
                                         const WasmEdge_ModuleInstanceContext *import);

void hs_WasmEdge_ExecutorInvoke(WasmEdge_Result *out,
                                 WasmEdge_ExecutorContext *cxt,
                                 const WasmEdge_FunctionInstanceContext *func,
                                 const WasmEdge_Value *params,
                                 uint32_t param_len,
                                 WasmEdge_Value *returns,
                                 uint32_t return_len);

// VM
void hs_WasmEdge_VMRunWasmFromFile(WasmEdge_Result *out,
                                    WasmEdge_VMContext *cxt,
                                    const char *path,
                                    const WasmEdge_String *func,
                                    const WasmEdge_Value *params,
                                    uint32_t param_len,
                                    WasmEdge_Value *returns,
                                    uint32_t return_len);

void hs_WasmEdge_VMRunWasmFromBuffer(WasmEdge_Result *out,
                                      WasmEdge_VMContext *cxt,
                                      const WasmEdge_Bytes *bytes,
                                      const WasmEdge_String *func,
                                      const WasmEdge_Value *params,
                                      uint32_t param_len,
                                      WasmEdge_Value *returns,
                                      uint32_t return_len);

void hs_WasmEdge_VMRunWasmFromASTModule(WasmEdge_Result *out,
                                         WasmEdge_VMContext *cxt,
                                         const WasmEdge_ASTModuleContext *ast,
                                         const WasmEdge_String *func,
                                         const WasmEdge_Value *params,
                                         uint32_t param_len,
                                         WasmEdge_Value *returns,
                                         uint32_t return_len);

void hs_WasmEdge_VMRegisterModuleFromFile(WasmEdge_Result *out,
                                           WasmEdge_VMContext *cxt,
                                           const WasmEdge_String *mod_name,
                                           const char *path);

void hs_WasmEdge_VMRegisterModuleFromBuffer(WasmEdge_Result *out,
                                             WasmEdge_VMContext *cxt,
                                             const WasmEdge_String *mod_name,
                                             const WasmEdge_Bytes *bytes);

void hs_WasmEdge_VMRegisterModuleFromImport(WasmEdge_Result *out,
                                             WasmEdge_VMContext *cxt,
                                             const WasmEdge_ModuleInstanceContext *import);

void hs_WasmEdge_VMLoadWasmFromFile(WasmEdge_Result *out,
                                     WasmEdge_VMContext *cxt,
                                     const char *path);

void hs_WasmEdge_VMLoadWasmFromBuffer(WasmEdge_Result *out,
                                       WasmEdge_VMContext *cxt,
                                       const WasmEdge_Bytes *bytes);

void hs_WasmEdge_VMLoadWasmFromASTModule(WasmEdge_Result *out,
                                          WasmEdge_VMContext *cxt,
                                          const WasmEdge_ASTModuleContext *ast);

void hs_WasmEdge_VMValidate(WasmEdge_Result *out, WasmEdge_VMContext *cxt);

void hs_WasmEdge_VMInstantiate(WasmEdge_Result *out, WasmEdge_VMContext *cxt);

void hs_WasmEdge_VMExecute(WasmEdge_Result *out,
                            WasmEdge_VMContext *cxt,
                            const WasmEdge_String *func,
                            const WasmEdge_Value *params,
                            uint32_t param_len,
                            WasmEdge_Value *returns,
                            uint32_t return_len);

void hs_WasmEdge_VMExecuteRegistered(WasmEdge_Result *out,
                                      WasmEdge_VMContext *cxt,
                                      const WasmEdge_String *mod_name,
                                      const WasmEdge_String *func,
                                      const WasmEdge_Value *params,
                                      uint32_t param_len,
                                      WasmEdge_Value *returns,
                                      uint32_t return_len);

// AOT Compiler
void hs_WasmEdge_CompilerCompile(WasmEdge_Result *out,
                                  WasmEdge_CompilerContext *cxt,
                                  const char *input_path,
                                  const char *output_path);

void hs_WasmEdge_CompilerCompileFromBuffer(WasmEdge_Result *out,
                                            WasmEdge_CompilerContext *cxt,
                                            const WasmEdge_Bytes *bytes,
                                            const char *output_path);

// Module instance add* (adds export and transfers ownership)
void hs_WasmEdge_ModuleInstanceAddFunction(WasmEdge_ModuleInstanceContext *cxt,
                                            const WasmEdge_String *name,
                                            WasmEdge_FunctionInstanceContext *func);

void hs_WasmEdge_ModuleInstanceAddTable(WasmEdge_ModuleInstanceContext *cxt,
                                         const WasmEdge_String *name,
                                         WasmEdge_TableInstanceContext *table);

void hs_WasmEdge_ModuleInstanceAddMemory(WasmEdge_ModuleInstanceContext *cxt,
                                          const WasmEdge_String *name,
                                          WasmEdge_MemoryInstanceContext *mem);

void hs_WasmEdge_ModuleInstanceAddGlobal(WasmEdge_ModuleInstanceContext *cxt,
                                         const WasmEdge_String *name,
                                         WasmEdge_GlobalInstanceContext *global);

// Limit and Instance creation helpers
WasmEdge_MemoryTypeContext *hs_WasmEdge_MemoryTypeCreate(
    bool has_max, uint64_t min_pages, uint64_t max_pages, bool shared, bool is64);

WasmEdge_TableTypeContext *hs_WasmEdge_TableTypeCreate(
    const WasmEdge_ValType *ref_type,
    bool has_max, uint64_t min_val, uint64_t max_val, bool shared, bool is64);

void hs_WasmEdge_LimitGetInfo(
    const WasmEdge_LimitContext *lim,
    bool *has_max, uint64_t *min_val, uint64_t *max_val, bool *shared, bool *is64);

typedef void (*hs_host_func_t)(
    void *data,
    const WasmEdge_CallingFrameContext *frame,
    const WasmEdge_Value *params,
    uint32_t param_len,
    WasmEdge_Value *returns,
    uint32_t return_len,
    WasmEdge_Result *res_out);

WasmEdge_FunctionInstanceContext *hs_WasmEdge_FunctionInstanceCreateBinding(
    const WasmEdge_FunctionTypeContext *type,
    hs_host_func_t hs_fn,
    void *data,
    uint64_t cost);

// Memory instance data operations
void hs_WasmEdge_MemoryInstanceGetData(WasmEdge_Result *out,
                                        WasmEdge_MemoryInstanceContext *cxt,
                                        uint8_t *data,
                                        uint32_t offset,
                                        uint32_t length);

void hs_WasmEdge_MemoryInstanceSetData(WasmEdge_Result *out,
                                        WasmEdge_MemoryInstanceContext *cxt,
                                        const uint8_t *data,
                                        uint32_t offset,
                                        uint32_t length);

void hs_WasmEdge_MemoryInstanceGrowPage(WasmEdge_Result *out,
                                         WasmEdge_MemoryInstanceContext *cxt,
                                         uint32_t page);

// Table instance data operations
void hs_WasmEdge_TableInstanceGetData(WasmEdge_Result *out,
                                       WasmEdge_TableInstanceContext *cxt,
                                       WasmEdge_Value *data,
                                       uint32_t offset);

void hs_WasmEdge_TableInstanceSetData(WasmEdge_Result *out,
                                       WasmEdge_TableInstanceContext *cxt,
                                       const WasmEdge_Value *data,
                                       uint32_t offset);

void hs_WasmEdge_TableInstanceGrow(WasmEdge_Result *out,
                                    WasmEdge_TableInstanceContext *cxt,
                                    uint32_t size);

// Global instance get/set
void hs_WasmEdge_GlobalInstanceGetValue(WasmEdge_Value *out,
                                         const WasmEdge_GlobalInstanceContext *cxt);

void hs_WasmEdge_GlobalInstanceSetValue(WasmEdge_Result *out,
                                         WasmEdge_GlobalInstanceContext *cxt,
                                         const WasmEdge_Value *val);

// Async results
void hs_WasmEdge_AsyncGet(WasmEdge_Result *out,
                           WasmEdge_Async *async,
                           WasmEdge_Value *returns,
                           uint32_t return_len);

// FunctionType shims (return structs by value in C, but created here via alloc)
WasmEdge_FunctionTypeContext *
hs_WasmEdge_FunctionTypeCreate(const WasmEdge_ValType *params,
                                uint32_t param_len,
                                const WasmEdge_ValType *returns,
                                uint32_t return_len);

// Import/Export type query shims (string out-params)
void hs_WasmEdge_ImportTypeGetModuleName(WasmEdge_String *out,
                                          const WasmEdge_ImportTypeContext *cxt);

void hs_WasmEdge_ImportTypeGetExternalName(WasmEdge_String *out,
                                            const WasmEdge_ImportTypeContext *cxt);

void hs_WasmEdge_ExportTypeGetExternalName(WasmEdge_String *out,
                                            const WasmEdge_ExportTypeContext *cxt);

void hs_WasmEdge_ModuleInstanceGetModuleName(WasmEdge_String *out,
                                              const WasmEdge_ModuleInstanceContext *cxt);

void hs_WasmEdge_PluginGetPluginName(WasmEdge_String *out,
                                      const WasmEdge_PluginContext *cxt);

void hs_WasmEdge_VMForceDeleteRegisteredModule(const WasmEdge_VMContext *cxt,
                                               const WasmEdge_String *name);

const WasmEdge_FunctionTypeContext *
hs_WasmEdge_VMGetFunctionType(const WasmEdge_VMContext *cxt,
                              const WasmEdge_String *func_name);

const WasmEdge_FunctionTypeContext *
hs_WasmEdge_VMGetFunctionTypeRegistered(const WasmEdge_VMContext *cxt,
                                        const WasmEdge_String *mod_name,
                                        const WasmEdge_String *func_name);

// Additional shims for struct-by-value parameters/returns
WasmEdge_ModuleInstanceContext *
hs_WasmEdge_ModuleInstanceCreate(const WasmEdge_String *name);

WasmEdge_ModuleInstanceContext *
hs_WasmEdge_ModuleInstanceCreateWithData(const WasmEdge_String *name,
                                        void *host_data,
                                        void (*finalizer)(void *));

WasmEdge_FunctionInstanceContext *
hs_WasmEdge_ModuleInstanceFindFunction(const WasmEdge_ModuleInstanceContext *cxt,
                                       const WasmEdge_String *name);

WasmEdge_TableInstanceContext *
hs_WasmEdge_ModuleInstanceFindTable(const WasmEdge_ModuleInstanceContext *cxt,
                                    const WasmEdge_String *name);

WasmEdge_MemoryInstanceContext *
hs_WasmEdge_ModuleInstanceFindMemory(const WasmEdge_ModuleInstanceContext *cxt,
                                     const WasmEdge_String *name);

WasmEdge_GlobalInstanceContext *
hs_WasmEdge_ModuleInstanceFindGlobal(const WasmEdge_ModuleInstanceContext *cxt,
                                     const WasmEdge_String *name);

WasmEdge_TagInstanceContext *
hs_WasmEdge_ModuleInstanceFindTag(const WasmEdge_ModuleInstanceContext *cxt,
                                  const WasmEdge_String *name);

const WasmEdge_ModuleInstanceContext *
hs_WasmEdge_StoreFindModule(const WasmEdge_StoreContext *cxt,
                            const WasmEdge_String *name);

const WasmEdge_PluginContext *
hs_WasmEdge_PluginFind(const WasmEdge_String *name);

WasmEdge_ModuleInstanceContext *
hs_WasmEdge_PluginCreateModule(const WasmEdge_PluginContext *cxt,
                               const WasmEdge_String *name);

const WasmEdge_ModuleInstanceContext *
hs_WasmEdge_VMGetRegisteredModule(const WasmEdge_VMContext *cxt,
                                  const WasmEdge_String *name);

void hs_WasmEdge_VMRegisterModuleFromASTModule(
    WasmEdge_Result *out,
    WasmEdge_VMContext *cxt,
    const WasmEdge_String *name,
    const WasmEdge_ASTModuleContext *ast);

void hs_WasmEdge_VMRegisterModuleFromImportWithAlias(
    WasmEdge_Result *out,
    WasmEdge_VMContext *cxt,
    const WasmEdge_String *name,
    const WasmEdge_ModuleInstanceContext *import_cxt);

WasmEdge_Async *hs_WasmEdge_VMAsyncExecute(
    WasmEdge_VMContext *cxt,
    const WasmEdge_String *func_name,
    const WasmEdge_Value *params,
    uint32_t param_len);

WasmEdge_Async *hs_WasmEdge_VMAsyncExecuteRegistered(
    WasmEdge_VMContext *cxt,
    const WasmEdge_String *mod_name,
    const WasmEdge_String *func_name,
    const WasmEdge_Value *params,
    uint32_t param_len);

WasmEdge_Async *hs_WasmEdge_VMAsyncRunWasmFromFile(
    WasmEdge_VMContext *cxt,
    const char *path,
    const WasmEdge_String *func_name,
    const WasmEdge_Value *params,
    uint32_t param_len);

WasmEdge_Async *hs_WasmEdge_VMAsyncRunWasmFromBytes(
    WasmEdge_VMContext *cxt,
    const WasmEdge_Bytes *bytes,
    const WasmEdge_String *func_name,
    const WasmEdge_Value *params,
    uint32_t param_len);

WasmEdge_Async *hs_WasmEdge_VMAsyncRunWasmFromASTModule(
    WasmEdge_VMContext *cxt,
    const WasmEdge_ASTModuleContext *ast,
    const WasmEdge_String *func_name,
    const WasmEdge_Value *params,
    uint32_t param_len);

WasmEdge_GlobalTypeContext *
hs_WasmEdge_GlobalTypeCreate(const WasmEdge_ValType *val_type,
                             enum WasmEdge_Mutability mut);

void hs_WasmEdge_GlobalTypeGetValType(const WasmEdge_GlobalTypeContext *cxt,
                                      WasmEdge_ValType *out);

WasmEdge_GlobalInstanceContext *
hs_WasmEdge_GlobalInstanceCreate(const WasmEdge_GlobalTypeContext *type,
                                 const WasmEdge_Value *val);

void hs_WasmEdge_TableTypeGetRefType(const WasmEdge_TableTypeContext *cxt,
                                     WasmEdge_ValType *out);

#ifdef __cplusplus
}
#endif

#endif // WASMEDGE_HS_SHIMS_H
