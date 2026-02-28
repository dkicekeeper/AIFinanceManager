//
//  TransactionConverterServiceProtocol.swift
//  AIFinanceManager
//
//  DEPRECATED — Phase 37: `convertRow()` merged into `EntityMappingServiceProtocol`.
//
//  The conversion step is now declared in `EntityMappingServiceProtocol` and implemented
//  by `EntityMappingService`. The separate converter protocol and service have been removed
//  because all resolved IDs (accountId, categoryId, subcategoryIds) originate from
//  EntityMappingService anyway — conversion is a natural continuation of mapping.
//
//  This file is kept as a tombstone to preserve git history context.
//  Remove this file in a future cleanup pass.
//
