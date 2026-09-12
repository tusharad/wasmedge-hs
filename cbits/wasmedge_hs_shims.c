// SPDX-License-Identifier: Apache-2.0
// wasmedge-hs: C shim implementations

#include "wasmedge_hs_shims.h"
#include <stdlib.h>
#include <string.h>

// =========================================================================
// String shims
// =========================================================================

void hs_WasmEdge_StringCreateByCString(WasmEdge_String *out, const char *str) {
  *out = WasmEdge_StringCreateByCString(str);
}

void hs_WasmEdge_StringCreateByBuffer(WasmEdge_String *out, const char *buf,
                                       uint32_t len) {
  *out = WasmEdge_StringCreateByBuffer(buf, len);
}

void hs_WasmEdge_StringWrap(WasmEdge_String *out, const char *buf,
                              uint32_t len) {
  *out = WasmEdge_StringWrap(buf, len);
}

bool hs_WasmEdge_StringIsEqual(const WasmEdge_String *s1,
                                const WasmEdge_String *s2) {
  return WasmEdge_StringIsEqual(*s1, *s2);
}

uint32_t hs_WasmEdge_StringCopy(const WasmEdge_String *str, char *buf,
                                 uint32_t len) {
  return WasmEdge_StringCopy(*str, buf, len);
}

void hs_WasmEdge_StringDelete(WasmEdge_String *str) {
  WasmEdge_StringDelete(*str);
  str->Length = 0;
  str->Buf = NULL;
}

uint32_t hs_WasmEdge_StringGetLength(const WasmEdge_String *str) {
  return str->Length;
}

const char *hs_WasmEdge_StringGetBuf(const WasmEdge_String *str) {
  return str->Buf;
}

// =========================================================================
// Bytes shims
// =========================================================================

void hs_WasmEdge_BytesCreate(WasmEdge_Bytes *out, const uint8_t *buf,
                              uint32_t len) {
  *out = WasmEdge_BytesCreate(buf, len);
}

void hs_WasmEdge_BytesWrap(WasmEdge_Bytes *out, const uint8_t *buf,
                            uint32_t len) {
  *out = WasmEdge_BytesWrap(buf, len);
}

void hs_WasmEdge_BytesDelete(WasmEdge_Bytes *bytes) {
  WasmEdge_BytesDelete(*bytes);
  bytes->Length = 0;
  bytes->Buf = NULL;
}

uint32_t hs_WasmEdge_BytesGetLength(const WasmEdge_Bytes *bytes) {
  return bytes->Length;
}

const uint8_t *hs_WasmEdge_BytesGetBuf(const WasmEdge_Bytes *bytes) {
  return bytes->Buf;
}

// =========================================================================
// Result shims
// =========================================================================

void hs_WasmEdge_Result_Success(WasmEdge_Result *out) {
  *out = WasmEdge_Result_Success;
}

void hs_WasmEdge_Result_Terminate(WasmEdge_Result *out) {
  *out = WasmEdge_Result_Terminate;
}

void hs_WasmEdge_Result_Fail(WasmEdge_Result *out) {
  *out = WasmEdge_Result_Fail;
}

bool hs_WasmEdge_ResultOK(const WasmEdge_Result *res) {
  return WasmEdge_ResultOK(*res);
}

void hs_WasmEdge_ResultGen(WasmEdge_Result *out,
                            WasmEdge_ErrCategory category,
                            uint32_t code) {
  *out = WasmEdge_ResultGen(category, code);
}

uint32_t hs_WasmEdge_ResultGetCode(const WasmEdge_Result *res) {
  return WasmEdge_ResultGetCode(*res);
}

WasmEdge_ErrCategory hs_WasmEdge_ResultGetCategory(const WasmEdge_Result *res) {
  return WasmEdge_ResultGetCategory(*res);
}

const char *hs_WasmEdge_ResultGetMessage(const WasmEdge_Result *res) {
  return WasmEdge_ResultGetMessage(*res);
}

// =========================================================================
// ValType shims
// =========================================================================

void hs_WasmEdge_ValTypeGenI32(WasmEdge_ValType *out)      { *out = WasmEdge_ValTypeGenI32(); }
void hs_WasmEdge_ValTypeGenI64(WasmEdge_ValType *out)      { *out = WasmEdge_ValTypeGenI64(); }
void hs_WasmEdge_ValTypeGenF32(WasmEdge_ValType *out)      { *out = WasmEdge_ValTypeGenF32(); }
void hs_WasmEdge_ValTypeGenF64(WasmEdge_ValType *out)      { *out = WasmEdge_ValTypeGenF64(); }
void hs_WasmEdge_ValTypeGenV128(WasmEdge_ValType *out)     { *out = WasmEdge_ValTypeGenV128(); }
void hs_WasmEdge_ValTypeGenFuncRef(WasmEdge_ValType *out)  { *out = WasmEdge_ValTypeGenFuncRef(); }
void hs_WasmEdge_ValTypeGenExternRef(WasmEdge_ValType *out){ *out = WasmEdge_ValTypeGenExternRef(); }

bool hs_WasmEdge_ValTypeIsEqual(const WasmEdge_ValType *t1,
                                 const WasmEdge_ValType *t2) {
  return WasmEdge_ValTypeIsEqual(*t1, *t2);
}
bool hs_WasmEdge_ValTypeIsI32(const WasmEdge_ValType *t)       { return WasmEdge_ValTypeIsI32(*t); }
bool hs_WasmEdge_ValTypeIsI64(const WasmEdge_ValType *t)       { return WasmEdge_ValTypeIsI64(*t); }
bool hs_WasmEdge_ValTypeIsF32(const WasmEdge_ValType *t)       { return WasmEdge_ValTypeIsF32(*t); }
bool hs_WasmEdge_ValTypeIsF64(const WasmEdge_ValType *t)       { return WasmEdge_ValTypeIsF64(*t); }
bool hs_WasmEdge_ValTypeIsV128(const WasmEdge_ValType *t)      { return WasmEdge_ValTypeIsV128(*t); }
bool hs_WasmEdge_ValTypeIsFuncRef(const WasmEdge_ValType *t)   { return WasmEdge_ValTypeIsFuncRef(*t); }
bool hs_WasmEdge_ValTypeIsExternRef(const WasmEdge_ValType *t) { return WasmEdge_ValTypeIsExternRef(*t); }
bool hs_WasmEdge_ValTypeIsRef(const WasmEdge_ValType *t)       { return WasmEdge_ValTypeIsRef(*t); }
bool hs_WasmEdge_ValTypeIsRefNull(const WasmEdge_ValType *t)   { return WasmEdge_ValTypeIsRefNull(*t); }

// =========================================================================
// Value shims
// =========================================================================

void hs_WasmEdge_ValueGenI32(WasmEdge_Value *out, int32_t val) {
  *out = WasmEdge_ValueGenI32(val);
}

void hs_WasmEdge_ValueGenI64(WasmEdge_Value *out, int64_t val) {
  *out = WasmEdge_ValueGenI64(val);
}

void hs_WasmEdge_ValueGenF32(WasmEdge_Value *out, float val) {
  *out = WasmEdge_ValueGenF32(val);
}

void hs_WasmEdge_ValueGenF64(WasmEdge_Value *out, double val) {
  *out = WasmEdge_ValueGenF64(val);
}

void hs_WasmEdge_ValueGenV128(WasmEdge_Value *out, uint64_t hi, uint64_t lo) {
  // Reconstruct uint128_t from two uint64_t words (via int128 helper)
  uint64_t words[2];
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
  words[0] = lo;
  words[1] = hi;
#else
  words[0] = hi;
  words[1] = lo;
#endif
  uint128_t v;
  memcpy(&v, words, 16);
  *out = WasmEdge_ValueGenV128(v);
}

void hs_WasmEdge_ValueGenFuncRef(WasmEdge_Value *out,
                                  const WasmEdge_FunctionInstanceContext *cxt) {
  *out = WasmEdge_ValueGenFuncRef(cxt);
}

void hs_WasmEdge_ValueGenExternRef(WasmEdge_Value *out, void *ref) {
  *out = WasmEdge_ValueGenExternRef(ref);
}

void hs_WasmEdge_ValueGenNullFuncRef(WasmEdge_Value *out) {
  *out = WasmEdge_ValueGenFuncRef(NULL);
}

void hs_WasmEdge_ValueGenNullExternRef(WasmEdge_Value *out) {
  *out = WasmEdge_ValueGenExternRef(NULL);
}

int32_t  hs_WasmEdge_ValueGetI32(const WasmEdge_Value *val) { return WasmEdge_ValueGetI32(*val); }
int64_t  hs_WasmEdge_ValueGetI64(const WasmEdge_Value *val) { return WasmEdge_ValueGetI64(*val); }
float    hs_WasmEdge_ValueGetF32(const WasmEdge_Value *val) { return WasmEdge_ValueGetF32(*val); }
double   hs_WasmEdge_ValueGetF64(const WasmEdge_Value *val) { return WasmEdge_ValueGetF64(*val); }

void hs_WasmEdge_ValueGetV128(const WasmEdge_Value *val, uint64_t *hi,
                               uint64_t *lo) {
  uint128_t v = WasmEdge_ValueGetV128(*val);
  uint64_t words[2];
  memcpy(words, &v, 16);
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
  *lo = words[0];
  *hi = words[1];
#else
  *hi = words[0];
  *lo = words[1];
#endif
}

bool hs_WasmEdge_ValueIsNullRef(const WasmEdge_Value *val) {
  return WasmEdge_ValueIsNullRef(*val);
}

const WasmEdge_FunctionInstanceContext *
hs_WasmEdge_ValueGetFuncRef(const WasmEdge_Value *val) {
  return WasmEdge_ValueGetFuncRef(*val);
}

void *hs_WasmEdge_ValueGetExternRef(const WasmEdge_Value *val) {
  return WasmEdge_ValueGetExternRef(*val);
}

void hs_WasmEdge_ValueGetType(const WasmEdge_Value *val, WasmEdge_ValType *out) {
  *out = val->Type;
}

// =========================================================================
// Value array helpers
// =========================================================================

WasmEdge_Value *hs_WasmEdge_ValueArrayAlloc(uint32_t n) {
  if (n == 0) return NULL;
  return (WasmEdge_Value *)calloc(n, sizeof(WasmEdge_Value));
}

void hs_WasmEdge_ValueArrayFree(WasmEdge_Value *arr) {
  free(arr);
}

void hs_WasmEdge_ValueArraySet(WasmEdge_Value *arr, uint32_t idx,
                                const WasmEdge_Value *val) {
  arr[idx] = *val;
}

void hs_WasmEdge_ValueArrayGet(const WasmEdge_Value *arr, uint32_t idx,
                                WasmEdge_Value *out) {
  *out = arr[idx];
}

// =========================================================================
// Execution shims
// =========================================================================

void hs_WasmEdge_LoaderParseFromFile(WasmEdge_Result *out,
                                      WasmEdge_LoaderContext *cxt,
                                      WasmEdge_ASTModuleContext **module,
                                      const char *path) {
  *out = WasmEdge_LoaderParseFromFile(cxt, module, path);
}

void hs_WasmEdge_LoaderParseFromBytes(WasmEdge_Result *out,
                                       WasmEdge_LoaderContext *cxt,
                                       WasmEdge_ASTModuleContext **module,
                                       const WasmEdge_Bytes *bytes) {
  *out = WasmEdge_LoaderParseFromBytes(cxt, module, *bytes);
}

void hs_WasmEdge_LoaderSerializeASTModule(WasmEdge_Result *out,
                                           WasmEdge_LoaderContext *cxt,
                                           const WasmEdge_ASTModuleContext *ast,
                                           WasmEdge_Bytes *buf) {
  *out = WasmEdge_LoaderSerializeASTModule(cxt, ast, buf);
}

void hs_WasmEdge_ValidatorValidate(WasmEdge_Result *out,
                                    WasmEdge_ValidatorContext *cxt,
                                    const WasmEdge_ASTModuleContext *module) {
  *out = WasmEdge_ValidatorValidate(cxt, module);
}

void hs_WasmEdge_ExecutorInstantiate(WasmEdge_Result *out,
                                      WasmEdge_ExecutorContext *cxt,
                                      WasmEdge_ModuleInstanceContext **mod_inst,
                                      WasmEdge_StoreContext *store,
                                      const WasmEdge_ASTModuleContext *ast) {
  *out = WasmEdge_ExecutorInstantiate(cxt, mod_inst, store, ast);
}

void hs_WasmEdge_ExecutorRegister(WasmEdge_Result *out,
                                   WasmEdge_ExecutorContext *cxt,
                                   WasmEdge_ModuleInstanceContext **mod_inst,
                                   WasmEdge_StoreContext *store,
                                   const WasmEdge_ASTModuleContext *ast,
                                   const WasmEdge_String *mod_name) {
  *out = WasmEdge_ExecutorRegister(cxt, mod_inst, store, ast, *mod_name);
}

void hs_WasmEdge_ExecutorRegisterImport(WasmEdge_Result *out,
                                         WasmEdge_ExecutorContext *cxt,
                                         WasmEdge_StoreContext *store,
                                         const WasmEdge_ModuleInstanceContext *import) {
  *out = WasmEdge_ExecutorRegisterImport(cxt, store, import);
}

void hs_WasmEdge_ExecutorInvoke(WasmEdge_Result *out,
                                 WasmEdge_ExecutorContext *cxt,
                                 const WasmEdge_FunctionInstanceContext *func,
                                 const WasmEdge_Value *params,
                                 uint32_t param_len,
                                 WasmEdge_Value *returns,
                                 uint32_t return_len) {
  *out = WasmEdge_ExecutorInvoke(cxt, func, params, param_len, returns,
                                  return_len);
}

void hs_WasmEdge_VMRunWasmFromFile(WasmEdge_Result *out,
                                    WasmEdge_VMContext *cxt,
                                    const char *path,
                                    const WasmEdge_String *func,
                                    const WasmEdge_Value *params,
                                    uint32_t param_len,
                                    WasmEdge_Value *returns,
                                    uint32_t return_len) {
  *out = WasmEdge_VMRunWasmFromFile(cxt, path, *func, params, param_len,
                                     returns, return_len);
}

void hs_WasmEdge_VMRunWasmFromBuffer(WasmEdge_Result *out,
                                      WasmEdge_VMContext *cxt,
                                      const WasmEdge_Bytes *bytes,
                                      const WasmEdge_String *func,
                                      const WasmEdge_Value *params,
                                      uint32_t param_len,
                                      WasmEdge_Value *returns,
                                      uint32_t return_len) {
  *out = WasmEdge_VMRunWasmFromBytes(cxt, *bytes, *func, params, param_len,
                                      returns, return_len);
}

void hs_WasmEdge_VMRunWasmFromASTModule(WasmEdge_Result *out,
                                         WasmEdge_VMContext *cxt,
                                         const WasmEdge_ASTModuleContext *ast,
                                         const WasmEdge_String *func,
                                         const WasmEdge_Value *params,
                                         uint32_t param_len,
                                         WasmEdge_Value *returns,
                                         uint32_t return_len) {
  *out = WasmEdge_VMRunWasmFromASTModule(cxt, ast, *func, params, param_len,
                                          returns, return_len);
}

void hs_WasmEdge_VMRegisterModuleFromFile(WasmEdge_Result *out,
                                           WasmEdge_VMContext *cxt,
                                           const WasmEdge_String *mod_name,
                                           const char *path) {
  *out = WasmEdge_VMRegisterModuleFromFile(cxt, *mod_name, path);
}

void hs_WasmEdge_VMRegisterModuleFromBuffer(WasmEdge_Result *out,
                                             WasmEdge_VMContext *cxt,
                                             const WasmEdge_String *mod_name,
                                             const WasmEdge_Bytes *bytes) {
  *out = WasmEdge_VMRegisterModuleFromBytes(cxt, *mod_name, *bytes);
}

void hs_WasmEdge_VMRegisterModuleFromImport(WasmEdge_Result *out,
                                             WasmEdge_VMContext *cxt,
                                             const WasmEdge_ModuleInstanceContext *import) {
  *out = WasmEdge_VMRegisterModuleFromImport(cxt, import);
}

void hs_WasmEdge_VMLoadWasmFromFile(WasmEdge_Result *out,
                                     WasmEdge_VMContext *cxt,
                                     const char *path) {
  *out = WasmEdge_VMLoadWasmFromFile(cxt, path);
}

void hs_WasmEdge_VMLoadWasmFromBuffer(WasmEdge_Result *out,
                                       WasmEdge_VMContext *cxt,
                                       const WasmEdge_Bytes *bytes) {
  *out = WasmEdge_VMLoadWasmFromBytes(cxt, *bytes);
}

void hs_WasmEdge_VMLoadWasmFromASTModule(WasmEdge_Result *out,
                                          WasmEdge_VMContext *cxt,
                                          const WasmEdge_ASTModuleContext *ast) {
  *out = WasmEdge_VMLoadWasmFromASTModule(cxt, ast);
}

void hs_WasmEdge_VMValidate(WasmEdge_Result *out, WasmEdge_VMContext *cxt) {
  *out = WasmEdge_VMValidate(cxt);
}

void hs_WasmEdge_VMInstantiate(WasmEdge_Result *out, WasmEdge_VMContext *cxt) {
  *out = WasmEdge_VMInstantiate(cxt);
}

void hs_WasmEdge_VMExecute(WasmEdge_Result *out,
                            WasmEdge_VMContext *cxt,
                            const WasmEdge_String *func,
                            const WasmEdge_Value *params,
                            uint32_t param_len,
                            WasmEdge_Value *returns,
                            uint32_t return_len) {
  *out = WasmEdge_VMExecute(cxt, *func, params, param_len, returns, return_len);
}

void hs_WasmEdge_VMExecuteRegistered(WasmEdge_Result *out,
                                      WasmEdge_VMContext *cxt,
                                      const WasmEdge_String *mod_name,
                                      const WasmEdge_String *func,
                                      const WasmEdge_Value *params,
                                      uint32_t param_len,
                                      WasmEdge_Value *returns,
                                      uint32_t return_len) {
  *out = WasmEdge_VMExecuteRegistered(cxt, *mod_name, *func, params, param_len,
                                       returns, return_len);
}

void hs_WasmEdge_CompilerCompile(WasmEdge_Result *out,
                                  WasmEdge_CompilerContext *cxt,
                                  const char *input_path,
                                  const char *output_path) {
  *out = WasmEdge_CompilerCompile(cxt, input_path, output_path);
}

void hs_WasmEdge_CompilerCompileFromBuffer(WasmEdge_Result *out,
                                            WasmEdge_CompilerContext *cxt,
                                            const WasmEdge_Bytes *bytes,
                                            const char *output_path) {
  *out = WasmEdge_CompilerCompileFromBytes(cxt, *bytes, output_path);
}

void hs_WasmEdge_ModuleInstanceAddFunction(WasmEdge_Result *out,
                                            WasmEdge_ModuleInstanceContext *cxt,
                                            const WasmEdge_String *name,
                                            WasmEdge_FunctionInstanceContext *func) {
  *out = WasmEdge_ModuleInstanceAddFunction(cxt, *name, func);
}

void hs_WasmEdge_ModuleInstanceAddTable(WasmEdge_Result *out,
                                         WasmEdge_ModuleInstanceContext *cxt,
                                         const WasmEdge_String *name,
                                         WasmEdge_TableInstanceContext *table) {
  *out = WasmEdge_ModuleInstanceAddTable(cxt, *name, table);
}

void hs_WasmEdge_ModuleInstanceAddMemory(WasmEdge_Result *out,
                                          WasmEdge_ModuleInstanceContext *cxt,
                                          const WasmEdge_String *name,
                                          WasmEdge_MemoryInstanceContext *mem) {
  *out = WasmEdge_ModuleInstanceAddMemory(cxt, *name, mem);
}

void hs_WasmEdge_ModuleInstanceAddGlobal(WasmEdge_Result *out,
                                          WasmEdge_ModuleInstanceContext *cxt,
                                          const WasmEdge_String *name,
                                          WasmEdge_GlobalInstanceContext *global) {
  *out = WasmEdge_ModuleInstanceAddGlobal(cxt, *name, global);
}

void hs_WasmEdge_MemoryInstanceGetData(WasmEdge_Result *out,
                                        WasmEdge_MemoryInstanceContext *cxt,
                                        uint8_t *data,
                                        uint32_t offset,
                                        uint32_t length) {
  *out = WasmEdge_MemoryInstanceGetData(cxt, data, offset, length);
}

void hs_WasmEdge_MemoryInstanceSetData(WasmEdge_Result *out,
                                        WasmEdge_MemoryInstanceContext *cxt,
                                        const uint8_t *data,
                                        uint32_t offset,
                                        uint32_t length) {
  *out = WasmEdge_MemoryInstanceSetData(cxt, data, offset, length);
}

void hs_WasmEdge_MemoryInstanceGrowPage(WasmEdge_Result *out,
                                         WasmEdge_MemoryInstanceContext *cxt,
                                         uint32_t page) {
  *out = WasmEdge_MemoryInstanceGrowPage(cxt, page);
}

void hs_WasmEdge_TableInstanceGetData(WasmEdge_Result *out,
                                       WasmEdge_TableInstanceContext *cxt,
                                       WasmEdge_Value *data,
                                       uint32_t offset) {
  *out = WasmEdge_TableInstanceGetData(cxt, data, offset);
}

void hs_WasmEdge_TableInstanceSetData(WasmEdge_Result *out,
                                       WasmEdge_TableInstanceContext *cxt,
                                       const WasmEdge_Value *data,
                                       uint32_t offset) {
  *out = WasmEdge_TableInstanceSetData(cxt, *data, offset);
}

void hs_WasmEdge_TableInstanceGrow(WasmEdge_Result *out,
                                    WasmEdge_TableInstanceContext *cxt,
                                    uint32_t size) {
  *out = WasmEdge_TableInstanceGrow(cxt, size);
}

void hs_WasmEdge_GlobalInstanceGetValue(WasmEdge_Value *out,
                                         const WasmEdge_GlobalInstanceContext *cxt) {
  *out = WasmEdge_GlobalInstanceGetValue(cxt);
}

void hs_WasmEdge_GlobalInstanceSetValue(WasmEdge_Result *out,
                                         WasmEdge_GlobalInstanceContext *cxt,
                                         const WasmEdge_Value *val) {
  *out = WasmEdge_GlobalInstanceSetValue(cxt, *val);
}

void hs_WasmEdge_AsyncGet(WasmEdge_Result *out,
                           WasmEdge_Async *async,
                           WasmEdge_Value *returns,
                           uint32_t return_len) {
  *out = WasmEdge_AsyncGet(async, returns, return_len);
}

WasmEdge_FunctionTypeContext *
hs_WasmEdge_FunctionTypeCreate(const WasmEdge_ValType *params,
                                uint32_t param_len,
                                const WasmEdge_ValType *returns,
                                uint32_t return_len) {
  return WasmEdge_FunctionTypeCreate(params, param_len, returns, return_len);
}

void hs_WasmEdge_ImportTypeGetModuleName(WasmEdge_String *out,
                                          const WasmEdge_ImportTypeContext *cxt) {
  *out = WasmEdge_ImportTypeGetModuleName(cxt);
}

void hs_WasmEdge_ImportTypeGetExternalName(WasmEdge_String *out,
                                            const WasmEdge_ImportTypeContext *cxt) {
  *out = WasmEdge_ImportTypeGetExternalName(cxt);
}

void hs_WasmEdge_ExportTypeGetExternalName(WasmEdge_String *out,
                                            const WasmEdge_ExportTypeContext *cxt) {
  *out = WasmEdge_ExportTypeGetExternalName(cxt);
}

void hs_WasmEdge_ModuleInstanceGetModuleName(WasmEdge_String *out,
                                              const WasmEdge_ModuleInstanceContext *cxt) {
  *out = WasmEdge_ModuleInstanceGetModuleName(cxt);
}

void hs_WasmEdge_PluginGetPluginName(WasmEdge_String *out,
                                      const WasmEdge_PluginContext *cxt) {
  *out = WasmEdge_PluginGetPluginName(cxt);
}
