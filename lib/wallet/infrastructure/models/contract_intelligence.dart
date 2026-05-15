class ContractIntelligence {
  final String status;
  final String chain;
  final String contractType;
  final List<String> findings;
  final int gasEstimate;
  final double riskScore;

  final String aiSummary;

  ContractIntelligence({
    required this.status,
    required this.chain,
    required this.contractType,
    required this.findings,
    required this.gasEstimate,
    required this.riskScore,
    required this.aiSummary,
  });
}
