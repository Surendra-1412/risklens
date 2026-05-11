import 'dart:convert';
import 'dart:io';

void main() async {
  final url = Uri.parse('https://api.rss2json.com/v1/api.json?rss_url=https%3A%2F%2Fcointelegraph.com%2Frss');
  final request = await HttpClient().getUrl(url);
  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();
  print(responseBody.substring(0, 500));
}
