//===--------------- MemberExprRewriter.h -----------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
#ifndef DPCT_MEMBEREXPR_H
#define DPCT_MEMBEREXPR_H

#include "CallExprRewriter.h"

namespace clang {
namespace dpct {

class MemberExprBaseRewriter {
protected:
  const MemberExpr *ME;

protected:
  MemberExprBaseRewriter(const MemberExpr *ME) : ME(ME) {}
public:
  virtual ~MemberExprBaseRewriter() {}
  virtual Optional<std::string> rewrite() = 0;
};

template <class Printer>
class MemberExprPrinterRewriter: Printer,  public MemberExprBaseRewriter {
public:
  template<class... ArgsT>
  MemberExprPrinterRewriter(const MemberExpr *ME, ArgsT &&...Args):
    Printer(std::forward<ArgsT>(Args)...), MemberExprBaseRewriter(ME) {}

  Optional<std::string> rewrite() override {
    std::string Result;
    llvm::raw_string_ostream OS(Result);
    Printer::print(OS);
    return OS.str();
  }
};

template <class BaseNameT, class MemberNameT>
class MemberExprFieldRewriter
    : public MemberExprPrinterRewriter<MemberExprPrinter<BaseNameT, MemberNameT>> {
public:
    MemberExprFieldRewriter(
      const MemberExpr *ME,
      const std::function<BaseNameT(const MemberExpr *)> &BaseNameCreator,
      const std::function<bool(const MemberExpr *)> &IsArrowCreator,
      const std::function<MemberNameT(const MemberExpr *)> &MemberExprCreator):
        MemberExprPrinterRewriter<MemberExprPrinter<BaseNameT, MemberNameT>>(ME,
          BaseNameCreator(ME), IsArrowCreator(ME), MemberExprCreator(ME)) {}
};

template <class BaseNameT, class IndexT>
class MemberExprSubscriptRewriter
    : public MemberExprPrinterRewriter<MemberExprSubscriptPrinter<BaseNameT, IndexT>> {
public:
    using BaseTy = MemberExprPrinterRewriter<MemberExprSubscriptPrinter<BaseNameT, IndexT>>;
    MemberExprSubscriptRewriter(
      const MemberExpr *ME,
      const std::function<BaseNameT(const MemberExpr *)> &BaseNameCreator,
      const std::function<IndexT(const MemberExpr *)> &IndexCreator):
        MemberExprPrinterRewriter<MemberExprSubscriptPrinter<BaseNameT, IndexT>>(ME,
          BaseNameCreator(ME), IndexCreator(ME)) {}
    Optional<std::string> rewrite() override {
      auto Result = BaseTy::rewrite();
      if (Result.has_value()) {
        if (const InitListExpr *ILE =
                DpctGlobalInfo::findAncestor<InitListExpr>(this->ME)) {
          // E.g.,
          // dim3 d3; int64_t{d3.x};
          // will be migratd to
          // sycl::range<3> d3; int64_t{d3[2]};
          //
          // 'd3[2]' should be cast to 'int64_t' to avoid 'size_t -> long' narrowing-down
          // error in initializer list. 'int64_t' is canonical to 'long'.
          if (ILE->getNumInits() == 1 &&
              DpctGlobalInfo::getUnqualifiedTypeName(
                  ILE->getType().getCanonicalType()) == "long") {
            std::string ResultCast;
            llvm::raw_string_ostream OS(ResultCast);
            OS << "static_cast<";
            OS << DpctGlobalInfo::getUnqualifiedTypeName(ILE->getType());
            OS << ">";
            OS << "(" + Result.value() + ")";
            return ResultCast;
          }
        }
      }
      return Result;
    }
};

class MemberExprRewriterFactoryBase {
  public:
  virtual std::shared_ptr<MemberExprBaseRewriter> create(const MemberExpr *ME) const = 0;
  virtual ~MemberExprRewriterFactoryBase() {}

  static std::unique_ptr<std::unordered_map<
    std::string, std::shared_ptr<MemberExprRewriterFactoryBase>>>
    MemberExprRewriterMap;

  static void initMemberExprRewriterMap();

  RulePriority Priority = RulePriority::Fallback;
};


template <class RewriterTy, class... TAs>
class MemberExprRewriterFactory : public MemberExprRewriterFactoryBase {
  std::tuple<TAs...> Initializer;

private:
  template <size_t... Idx>
  inline std::shared_ptr<MemberExprBaseRewriter>
  createRewriter(const MemberExpr *ME, std::index_sequence<Idx...>) const {
    return std::shared_ptr<RewriterTy>(new RewriterTy(ME, std::get<Idx>(Initializer)...));
  }

public:
  MemberExprRewriterFactory(TAs... TemplateArgs)
      : Initializer(std::forward<TAs>(TemplateArgs)...) {}

  std::shared_ptr<MemberExprBaseRewriter> create(const MemberExpr *ME) const override{
    return createRewriter(ME, std::index_sequence_for<TAs...>());
  }

};

} // namespace dpct
} // namespace clang

#endif
