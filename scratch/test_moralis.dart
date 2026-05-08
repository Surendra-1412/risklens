import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final String moralisApiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJub25jZSI6ImYyMTE4N2MxLTE4NzAtNDU0MC1hYzIwLTc3NTc4NDRhYjFjNCIsIm9yZ0lkIjoiNTEzODg4IiwidXNlcklkIjoiNTI4ODExIiwidHlwZUlkIjoiOTQ2YTI0ZGMtODdkNC00YzNiLTlmN2UtNTQzZjA3MDc2OTAyIiwidHlwZSI6IlBST0pFQ1QiLCJpYXQiOjE3Nzc3Mzg0NzMsImV4cCI6NDkzMzQ5ODQ3M30.MRhG1_u1iLfLPI77pteOnlpyQgvNyaDTzt2hm1hwOZA";
  final String address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045";
  final String chain = "eth";

  print("Testing Moralis Unified History API...");
  final res = await http.get(
    Uri.parse("https://deep-index.moralis.io/api/v2.2/wallets/$address/history?chain=$chain&limit=5"),
    headers: {"X-API-Key": moralisApiKey, "accept": "application/json"},
  );

  print("Status Code: ${res.statusCode}");
  if (res.statusCode == 200) {
    final data = jsonDecode(res.body);
    final results = data['result'] as List? ?? [];
    print("Found ${results.length} transactions.");
    if (results.isNotEmpty) {
      print("First TX summary: ${results[0]['summary']}");
    }
  } else {
    print("Error: ${res.body}");
  }
}
