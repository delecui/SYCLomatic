//===--------------- MemberExprRewriter.cpp ---------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "MemberExprRewriter.h"

namespace clang {
namespace dpct {

template <class BaseT, class MemberArgsT>
std::shared_ptr<MemberExprRewriterFactoryBase> createMemberRewriterFactory(
    std::function<BaseT(const MemberExpr *)> BaseCreator,
    std::function<bool(const MemberExpr *)> IsArrow,
    std::function<MemberArgsT(const MemberExpr *)> MemCreator)
{
  return std::make_shared<MemberExprRewriterFactory<
                          MemberExprFieldRewriter<BaseT, MemberArgsT>,
                          std::function<BaseT(const MemberExpr *)>,
                          std::function<bool(const MemberExpr *)>,
                          std::function<MemberArgsT(const MemberExpr *)>>
                          >(BaseCreator, IsArrow, MemCreator);
}

template <class BaseT, class IndexT>
std::shared_ptr<MemberExprRewriterFactoryBase>
createMemberSubscriptRewriterFactory(
    std::function<BaseT(const MemberExpr *)> BaseCreator,
    std::function<IndexT(const MemberExpr *)> IndexCreator) {
  return std::make_shared<
      MemberExprRewriterFactory<MemberExprSubscriptRewriter<BaseT, IndexT>,
                                std::function<BaseT(const MemberExpr *)>,
                                std::function<IndexT(const MemberExpr *)>>>(
      BaseCreator, IndexCreator);
}

std::function<std::string(const MemberExpr *)> makeMemberBase() {
  return [=] (const MemberExpr *ME) -> std::string {
    auto Base = ME->getBase()->IgnoreImpCasts();
    if (!Base)
      return "";
    return getStmtSpelling(Base);
  };
}

std::function<std::string(const MemberExpr *)> makeMemberSubsctiptBase() {
  return [=](const MemberExpr *ME) -> std::string {
    auto Base = ME->getBase()->IgnoreImpCasts();
    if (!Base)
      return "";
    std::string Result = getStmtSpelling(Base);
    if (Base->getType()->isPointerType()) {
      Result = "(*" + Result + ")";
    }
    return Result;
  };
}

std::function<bool(const MemberExpr *)> isArrow() {
  return [=] (const MemberExpr *ME) -> bool {
    auto Base = ME->getBase()->IgnoreImpCasts();
    if (Base->getType()->isPointerType())
      return true;
    return false;
  };
}

std::function<std::string(const MemberExpr *)>
                makeMemberGetCall(std::string FuncName) {
  return [=] (const MemberExpr * ME) -> std::string {
    return FuncName + "()";
  };
}

std::function<std::string(const MemberExpr *)> makeSubscriptIndex() {
  return [=](const MemberExpr *ME) {
    std::string NewString = "";
    auto Search = MapNames::Dim3MemberNamesMap.find(
        ME->getMemberNameInfo().getAsString());
    if (Search != MapNames::Dim3MemberNamesMap.end()) {
      NewString = Search->second;
    }
    return NewString;
  };
}

std::unique_ptr<std::unordered_map<
        std::string, std::shared_ptr<MemberExprRewriterFactoryBase>>>
        MemberExprRewriterFactoryBase::MemberExprRewriterMap;

void MemberExprRewriterFactoryBase::initMemberExprRewriterMap() {
    MemberExprRewriterMap = std::make_unique<std::unordered_map<
      std::string, std::shared_ptr<MemberExprRewriterFactoryBase>>>(
        std::unordered_map<std::string,
                         std::shared_ptr<MemberExprRewriterFactoryBase>>({


#define CALL(...) makeCallExprCreator(__VA_ARGS__)
#define MEMBER_REWRITE_ENTRY(Name, Factory) {Name, Factory},
#define MEMBER_FACTORY(...) createMemberRewriterFactory(__VA_ARGS__)
#define MEM_BASE makeMemberBase()
#define MEM_CALL(x) makeMemberGetCall(x)
#define IS_ARROW isArrow()
#define MEMBER_SUBSCRIPT_FACTORY(...) createMemberSubscriptRewriterFactory(__VA_ARGS__)
#define MEM_SUBSCRIPT_BASE makeMemberSubsctiptBase()
#define SUBSCRIPT_INDEX makeSubscriptIndex()
#include "APINamesMemberExpr.inc"
#undef MEMBER_REWRITE_ENTRY
#undef MEMBER_FACTORY
#undef MEM_BASE
#undef MEM_ATTR
#undef MEMBER_SUBSCRIPT_FACTORY
#undef MEM_SUBSCRIPT_BASE
#undef SUBSCRIPT_INDEX
      }));
}
} // namespace dpct
} // namespace clang

