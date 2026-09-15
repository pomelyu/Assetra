import 'money.dart';

enum AccountType { general, stock, investment }

enum TransactionKind {
  stockBuy,
  stockSell,
  stockDividend,
  accountTransfer,
  accountIncome,
  accountExpense,
  investmentBuy,
  investmentSell,
  investmentInterest,
  investmentPnlAdjustment,
}

enum TransactionDirection { incoming, outgoing }

enum AccountStatus { active, archived, all }

enum ThemeModeSetting { system, light, dark }

enum MarketUpdateMode { manual, every15Minutes, afterMarketClose }

enum ReportGroupBy { category, account }

enum TrendPeriod { threeMonths, sixMonths, oneYear, threeYears, all }

typedef AccountId = String;
typedef CategoryId = String;
typedef SecurityId = String;
typedef TransactionId = String;

class Page<T> {
  final List<T> items;
  final String? nextCursor;
  const Page({required this.items, this.nextCursor});
}

class CreateAccountInput {
  final String name, categoryId, currencyCode;
  final num initialCost, initialValue;
  final String? note;
  const CreateAccountInput({
    required this.name,
    required this.categoryId,
    required this.currencyCode,
    required this.initialCost,
    required this.initialValue,
    this.note,
  });
}

class CreateInvestmentAccountInput extends CreateAccountInput {
  final AccountType accountType;
  final String fundingAccountId;
  const CreateInvestmentAccountInput({
    required super.name,
    required super.categoryId,
    required super.currencyCode,
    required super.initialCost,
    required super.initialValue,
    super.note,
    required this.accountType,
    required this.fundingAccountId,
  });
}

class UpdateAccountInput {
  final String name, categoryId, currencyCode;
  final num initialCost, initialValue;
  final String? note, fundingAccountId;
  const UpdateAccountInput({
    required this.name,
    required this.categoryId,
    required this.currencyCode,
    required this.initialCost,
    required this.initialValue,
    this.note,
    this.fundingAccountId,
  });
}

class ResolveSecurityInput {
  final String symbol, name, marketCode, currencyCode;
  final String? quoteSymbol;
  const ResolveSecurityInput({
    required this.symbol,
    required this.name,
    required this.marketCode,
    required this.currencyCode,
    this.quoteSymbol,
  });
}

sealed class StockTransactionInput {
  final String occurredAt, securityId, stockAccountId, fundingAccountId;
  final String? note;
  const StockTransactionInput({
    required this.occurredAt,
    required this.securityId,
    required this.stockAccountId,
    required this.fundingAccountId,
    this.note,
  });
  TransactionKind get kind;
}

class StockBuyInput extends StockTransactionInput {
  final ShareQuantity quantity;
  final Money unitPrice, fee;
  const StockBuyInput({
    required super.occurredAt,
    required super.securityId,
    required super.stockAccountId,
    required super.fundingAccountId,
    super.note,
    required this.quantity,
    required this.unitPrice,
    required this.fee,
  });
  @override
  TransactionKind get kind => TransactionKind.stockBuy;
}

class StockSellInput extends StockTransactionInput {
  final ShareQuantity quantity;
  final Money unitPrice, fee;
  const StockSellInput({
    required super.occurredAt,
    required super.securityId,
    required super.stockAccountId,
    required super.fundingAccountId,
    super.note,
    required this.quantity,
    required this.unitPrice,
    required this.fee,
  });
  @override
  TransactionKind get kind => TransactionKind.stockSell;
}

class StockDividendInput extends StockTransactionInput {
  final Money dividendAmount;
  const StockDividendInput({
    required super.occurredAt,
    required super.securityId,
    required super.stockAccountId,
    required super.fundingAccountId,
    super.note,
    required this.dividendAmount,
  });
  @override
  TransactionKind get kind => TransactionKind.stockDividend;
}

sealed class AccountTransactionInput {
  final String occurredAt;
  final String? note;
  const AccountTransactionInput({required this.occurredAt, this.note});
  TransactionKind get kind;
}

class AccountTransferInput extends AccountTransactionInput {
  final String sourceAccountId, targetAccountId;
  final Money sourceAmount, targetAmount;
  const AccountTransferInput({
    required super.occurredAt,
    super.note,
    required this.sourceAccountId,
    required this.targetAccountId,
    required this.sourceAmount,
    required this.targetAmount,
  });
  @override
  TransactionKind get kind => TransactionKind.accountTransfer;
}

class AccountIncomeInput extends AccountTransactionInput {
  final String targetAccountId;
  final Money targetAmount;
  const AccountIncomeInput({
    required super.occurredAt,
    super.note,
    required this.targetAccountId,
    required this.targetAmount,
  });
  @override
  TransactionKind get kind => TransactionKind.accountIncome;
}

class AccountExpenseInput extends AccountTransactionInput {
  final String sourceAccountId;
  final Money sourceAmount;
  const AccountExpenseInput({
    required super.occurredAt,
    super.note,
    required this.sourceAccountId,
    required this.sourceAmount,
  });
  @override
  TransactionKind get kind => TransactionKind.accountExpense;
}

class InvestmentBuyInput extends AccountTransactionInput {
  final String investmentAccountId, sourceAccountId;
  final Money amount, fee;
  const InvestmentBuyInput({
    required super.occurredAt,
    super.note,
    required this.investmentAccountId,
    required this.sourceAccountId,
    required this.amount,
    required this.fee,
  });
  @override
  TransactionKind get kind => TransactionKind.investmentBuy;
}

class InvestmentSellInput extends AccountTransactionInput {
  final String investmentAccountId, targetAccountId;
  final Money amount, fee;
  const InvestmentSellInput({
    required super.occurredAt,
    super.note,
    required this.investmentAccountId,
    required this.targetAccountId,
    required this.amount,
    required this.fee,
  });
  @override
  TransactionKind get kind => TransactionKind.investmentSell;
}

class InvestmentInterestInput extends AccountTransactionInput {
  final String investmentAccountId, targetAccountId;
  final Money amount;
  const InvestmentInterestInput({
    required super.occurredAt,
    super.note,
    required this.investmentAccountId,
    required this.targetAccountId,
    required this.amount,
  });
  @override
  TransactionKind get kind => TransactionKind.investmentInterest;
}

class InvestmentPnlAdjustmentInput extends AccountTransactionInput {
  final String investmentAccountId;
  final Money valueAdjustment;
  const InvestmentPnlAdjustmentInput({
    required super.occurredAt,
    super.note,
    required this.investmentAccountId,
    required this.valueAdjustment,
  });
  @override
  TransactionKind get kind => TransactionKind.investmentPnlAdjustment;
}

class AccountDetail {
  final String id, name, categoryId, currencyCode;
  final AccountType accountType;
  final Money cost;
  final Money? value;
  final Money realizedPnl, unrealizedPnl;
  final bool isArchived, isValuationComplete;
  const AccountDetail({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.currencyCode,
    required this.accountType,
    required this.cost,
    required this.value,
    required this.realizedPnl,
    required this.unrealizedPnl,
    required this.isArchived,
    required this.isValuationComplete,
  });
}

class AccountTransactionItem {
  final String id, occurredAt;
  final int entryOrder;
  final TransactionKind kind;
  final String? note;
  const AccountTransactionItem({
    required this.id,
    required this.occurredAt,
    required this.entryOrder,
    required this.kind,
    this.note,
  });
}

class SecurityOption {
  final String id, symbol, name, marketCode, currencyCode;
  const SecurityOption({
    required this.id,
    required this.symbol,
    required this.name,
    required this.marketCode,
    required this.currencyCode,
  });
}

class CategorySummary {
  final String id, name;
  final int colorArgb, sortOrder, accountUsageCount;
  const CategorySummary({
    required this.id,
    required this.name,
    required this.colorArgb,
    required this.sortOrder,
    required this.accountUsageCount,
  });
}

class CreateCategoryInput {
  final String name;
  final int colorArgb;
  const CreateCategoryInput({required this.name, required this.colorArgb});
}

class UpdateCategoryInput extends CreateCategoryInput {
  const UpdateCategoryInput({required super.name, required super.colorArgb});
}

class AppSettings {
  final ThemeModeSetting themeMode;
  final String languageCode;
  final MarketUpdateMode marketUpdateMode;
  final bool isBiometricLockEnabled;
  const AppSettings({
    required this.themeMode,
    required this.languageCode,
    required this.marketUpdateMode,
    required this.isBiometricLockEnabled,
  });
}

class AppSettingsPatch {
  final ThemeModeSetting? themeMode;
  final String? languageCode;
  final MarketUpdateMode? marketUpdateMode;
  const AppSettingsPatch({
    this.themeMode,
    this.languageCode,
    this.marketUpdateMode,
  });
}

class ManagedAccountSummary {
  final AccountDetail detail;
  final int fundingDependencyCount;
  const ManagedAccountSummary({
    required this.detail,
    required this.fundingDependencyCount,
  });
}

class AccountSummary {
  final AccountDetail detail;
  const AccountSummary(this.detail);
}

class AssetOverview {
  final List<AccountSummary> accounts;
  final Money? totalCost, totalValue;
  final bool isValuationComplete;
  const AssetOverview({
    required this.accounts,
    required this.totalCost,
    required this.totalValue,
    required this.isValuationComplete,
  });
}

class StockPositionSummary {
  final String securityId, symbol, name;
  final Money cost;
  final Money? value;

  /// Actual number of shares; database scaling is not exposed.
  final double quantityUnits;
  const StockPositionSummary({
    required this.securityId,
    required this.symbol,
    required this.name,
    required this.cost,
    required this.value,
    required this.quantityUnits,
  });
}

class StockOverview {
  final List<StockPositionSummary> positions;
  final Money? totalCost, totalValue;
  final bool isValuationComplete;
  const StockOverview({
    required this.positions,
    required this.totalCost,
    required this.totalValue,
    required this.isValuationComplete,
  });
}

class StockDetail extends StockPositionSummary {
  final Money realizedPnl, dividendIncome;
  const StockDetail({
    required super.securityId,
    required super.symbol,
    required super.name,
    required super.cost,
    required super.value,
    required super.quantityUnits,
    required this.realizedPnl,
    required this.dividendIncome,
  });
}

class StockTransactionPreview {
  final Money settlementAmount;
  const StockTransactionPreview(this.settlementAmount);
}

class AccountTransactionPreview {
  final Money? sourceChange,
      targetChange,
      investmentCostChange,
      investmentValueChange,
      realizedPnlChange;
  const AccountTransactionPreview({
    this.sourceChange,
    this.targetChange,
    this.investmentCostChange,
    this.investmentValueChange,
    this.realizedPnlChange,
  });
}

class StockTransactionFormData {
  final List<SecurityOption> securities;
  final StockTransactionInput? existing;
  const StockTransactionFormData({required this.securities, this.existing});
}

class AccountTransactionFormData {
  final AccountTransactionInput? existing;
  const AccountTransactionFormData({this.existing});
}

class AccountEditorData {
  final AccountDetail? existing;
  final List<CategorySummary> categories;
  final Money? initialCost, initialValue;
  final String? note;
  const AccountEditorData({
    this.existing,
    required this.categories,
    this.initialCost,
    this.initialValue,
    this.note,
  });
}

class InvestmentAccountEditorData extends AccountEditorData {
  final AccountType? createAccountType;
  final List<AccountDetail> fundingAccounts;
  const InvestmentAccountEditorData({
    super.existing,
    required super.categories,
    super.initialCost,
    super.initialValue,
    super.note,
    this.createAccountType,
    required this.fundingAccounts,
  });
}

class AllocationItem {
  final String categoryId, name;
  final int baseValue;
  final double percentage;
  const AllocationItem({
    required this.categoryId,
    required this.name,
    required this.baseValue,
    required this.percentage,
  });
}

class AllocationReport {
  final List<AllocationItem> items;
  final int totalBaseValue;
  final bool isValuationComplete;
  const AllocationReport({
    required this.items,
    required this.totalBaseValue,
    required this.isValuationComplete,
  });
}

class CostValueItem {
  final String id, name;
  final int baseCost, baseValue;
  const CostValueItem({
    required this.id,
    required this.name,
    required this.baseCost,
    required this.baseValue,
  });
}

class CostValueReport {
  final List<CostValueItem> items;
  const CostValueReport(this.items);
}

class TrendPoint {
  final String date;
  final int baseCost, baseValue, baseRealizedPnl;
  final bool isNow;
  const TrendPoint({
    required this.date,
    required this.baseCost,
    required this.baseValue,
    required this.baseRealizedPnl,
    required this.isNow,
  });
}

class HistoricalTrendReport {
  final List<TrendPoint> points;
  final bool isCurrentValuationComplete;
  const HistoricalTrendReport({
    required this.points,
    required this.isCurrentValuationComplete,
  });
}

class MarketRefreshResult {
  final int quoteSuccesses, rateSuccesses;
  final List<String> failures;
  const MarketRefreshResult({
    required this.quoteSuccesses,
    required this.rateSuccesses,
    required this.failures,
  });
}

class ExportResult {
  final String path;
  final int tableCount;
  const ExportResult({required this.path, required this.tableCount});
}

class BackupInspection {
  final String sourcePath, schemaVersion, createdAt;
  final Map<String, int> rowCounts;
  const BackupInspection({
    required this.sourcePath,
    required this.schemaVersion,
    required this.createdAt,
    required this.rowCounts,
  });
}

class ImportResult {
  final Map<String, int> rowCounts;
  const ImportResult(this.rowCounts);
}
