import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ScamAlert {
  final String title;
  final String summary;
  final String sourceName;
  final String url;
  final DateTime timestamp;
  final String imageUrl;
  int score;

  ScamAlert({
    required this.title,
    required this.summary,
    required this.sourceName,
    required this.url,
    required this.timestamp,
    required this.imageUrl,
    this.score = 0,
  });
}

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  bool _isLoading = true;
  List<ScamAlert> _newsItems = [];
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _fetchNews();
  }

  String _stripHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<List<ScamAlert>> fetchReddit() async {
    try {
      final response = await http.get(Uri.parse('https://www.reddit.com/r/cryptoscams/new.json'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final children = data['data']['children'] as List;
        return children.map((c) {
          final d = c['data'];
          final title = d['title'] ?? '';
          final content = d['selftext'] ?? '';
          final url = d['url'] ?? 'https://reddit.com${d['permalink']}';
          final ts = d['created_utc'] != null 
              ? DateTime.fromMillisecondsSinceEpoch((d['created_utc'] * 1000).toInt()) 
              : DateTime.now();
          
          String img = '';
          if (d['preview'] != null && d['preview']['images'] != null && d['preview']['images'].isNotEmpty) {
             img = d['preview']['images'][0]['source']['url'] ?? '';
             img = img.replaceAll('&amp;', '&');
          }
          
          return ScamAlert(
            title: title,
            summary: content.length > 200 ? content.substring(0, 200) + '...' : content,
            sourceName: 'Reddit',
            url: url,
            timestamp: ts,
            imageUrl: img,
          );
        }).toList();
      }
    } catch(e) {}
    return [];
  }

  Future<List<ScamAlert>> fetchRss(String rssUrl, String sourceName) async {
    try {
      final response = await http.get(Uri.parse("https://api.rss2json.com/v1/api.json?rss_url=${Uri.encodeComponent(rssUrl)}"));
      if (response.statusCode == 200) {
         final data = jsonDecode(response.body);
         if (data['status'] == 'ok') {
            final items = data['items'] as List;
            return items.map((item) {
               final title = item['title'] ?? '';
               final content = _stripHtml(item['content'] ?? item['description'] ?? '');
               final url = item['link'] ?? '';
               final pubDate = item['pubDate'] ?? '';
               DateTime ts = DateTime.now();
               try { ts = DateFormat("yyyy-MM-dd HH:mm:ss").parse(pubDate); } catch(e){}
               
               String img = item['thumbnail'] ?? '';
               if (img.isEmpty && item['enclosure'] != null) img = item['enclosure']['link'] ?? '';
               
               if (img.isNotEmpty) {
                 img = "https://wsrv.nl/?url=${Uri.encodeComponent(img)}";
               }
               
               return ScamAlert(
                 title: title,
                 summary: content.length > 200 ? content.substring(0, 200) + '...' : content,
                 sourceName: sourceName,
                 url: url,
                 timestamp: ts,
                 imageUrl: img,
               );
            }).toList();
         }
      }
    } catch(e){}
    return [];
  }

  bool isDuplicate(List<ScamAlert> list, ScamAlert newItem) {
    for (var item in list) {
      final words1 = item.title.toLowerCase().split(' ').toSet();
      final words2 = newItem.title.toLowerCase().split(' ').toSet();
      if (words1.isEmpty || words2.isEmpty) continue;
      final intersection = words1.intersection(words2).length;
      if (intersection > (words1.length * 0.6)) return true;
    }
    return false;
  }

  Future<void> _fetchNews() async {
    try {
      final responses = await Future.wait([
        fetchReddit(),
        fetchRss('https://www.coindesk.com/arc/outboundfeeds/rss/', 'CoinDesk'),
        fetchRss('https://decrypt.co/feed', 'Decrypt'),
        fetchRss('https://www.theblock.co/api/rss', 'The Block'),
      ]);

      List<ScamAlert> allAlerts = responses.expand((x) => x).toList();

      final keywords = ['scam', 'fraud', 'rug pull', 'hack', 'exploit', 'phishing', 'drained', 'stolen'];
      List<ScamAlert> filtered = [];

      for (var alert in allAlerts) {
        int score = 0;
        final text = (alert.title + " " + alert.summary).toLowerCase();
        for (var word in keywords) {
          if (text.contains(word)) score += 10;
        }
        
        if (text.contains('hack') || text.contains('exploit')) score += 5;
        if (text.contains('rug pull')) score += 15;

        alert.score = score;
        
        if (score >= 10) {
           if (!isDuplicate(filtered, alert)) {
              filtered.add(alert);
           }
        }
      }

      filtered.sort((a, b) {
        int scoreCmp = b.score.compareTo(a.score);
        if (scoreCmp != 0) return scoreCmp;
        return b.timestamp.compareTo(a.timestamp);
      });

      if (mounted) {
        setState(() {
          _newsItems = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  Widget _buildGradientPlaceholder(double size, String sourceName) {
    final isReddit = sourceName.toLowerCase() == 'reddit';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isReddit ? const Color(0xFFFF4500) : Colors.grey.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Center(
        child: Icon(
          isReddit ? Icons.reddit : Icons.security,
          color: isReddit ? Colors.white : Colors.grey,
          size: size * 0.4,
        ),
      ),
    );
  }

  Widget _buildImage(ScamAlert item, double size) {
    final url = item.imageUrl;
    if (url.isEmpty || url.contains('cointelegraph')) {
      return _buildGradientPlaceholder(size, item.sourceName);
    }
    return Image.network(
      url, 
      fit: BoxFit.cover,
      width: size,
      height: size,
      errorBuilder: (_,__,___) => _buildGradientPlaceholder(size, item.sourceName),
    );
  }

  Widget _buildSkeletonCard(bool isDark) {
    return Container(
       height: 120.h,
       margin: const EdgeInsets.only(bottom: 16),
       decoration: BoxDecoration(
         color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04), 
         borderRadius: BorderRadius.circular(24.r),
       ),
    );
  }

  Widget _buildNewsCard(ScamAlert item, bool isDark) {
    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.1),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => NewsDetailScreen(item: item)),
                );
              },
              splashColor: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1),
              highlightColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
              child: Padding(
                padding: EdgeInsets.all(12.r),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image on left
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16.r),
                      child: _buildImage(item, 90.w),
                    ),
                    SizedBox(width: 14.w),
                    // Title and Source
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.playfairDisplay(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 16.sp,
                              height: 1.2,
                            ),
                          ),
                          SizedBox(height: 12.h),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  item.sourceName.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.lato(
                                    color: Colors.blueAccent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11.sp,
                                    letterSpacing: 0.5.w,
                                  ),
                                ),
                              ),
                              SizedBox(width: 8.w),
                              Text(
                                timeAgo(item.timestamp),
                                style: GoogleFonts.lato(
                                  color: isDark ? Colors.white38 : Colors.black38,
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF5F5F7),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
            title: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1),
                  width: 1.w,
                ),
              ),
              child: Text(
                "Scams & Fraud",
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 24.sp,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: 0.5.w,
                ),
              ),
            ),
          ),
          if (_isLoading)
            SliverPadding(
              padding: EdgeInsets.only(left: 16.w, right: 16.w, top: 16.h, bottom: 120.h),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildSkeletonCard(isDark),
                  childCount: 5,
                ),
              ),
            )
          else if (_errorMessage.isNotEmpty)
            SliverFillRemaining(
              child: Center(child: Text("Error: $_errorMessage")),
            )
          else if (_newsItems.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  "No active scam alerts right now",
                  style: GoogleFonts.lato(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 16.sp,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.only(left: 16.w, right: 16.w, top: 16.h, bottom: 120.h),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return _buildNewsCard(_newsItems[index], isDark);
                  },
                  childCount: _newsItems.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NewsDetailScreen extends StatelessWidget {
  final ScamAlert item;

  const NewsDetailScreen({super.key, required this.item});

  Future<void> _openOriginal() async {
    final uri = Uri.parse(item.url);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.inAppWebView)) {
        throw Exception('Could not launch ${item.url}');
      }
    } catch (e) {
      debugPrint("Could not launch URL: $e");
    }
  }

  String timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  Widget _buildGradientPlaceholder() {
    final isReddit = item.sourceName.toLowerCase() == 'reddit';
    return Container(
      decoration: BoxDecoration(
        color: isReddit ? const Color(0xFFFF4500) : null,
        gradient: isReddit ? null : const LinearGradient(
          colors: [Color(0xFF2C3E50), Color(0xFF000000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      ),
      child: Center(
        child: Icon(
          isReddit ? Icons.reddit : Icons.security,
          color: isReddit ? Colors.white : Colors.white24,
          size: 64,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    String tag = "Security Alert";
    final text = (item.title + " " + item.summary).toLowerCase();
    if (text.contains('phishing')) tag = "Phishing";
    else if (text.contains('rug pull')) tag = "Rug Pull";
    else if (text.contains('exploit')) tag = "Exploit";

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF5F5F7),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Large Header Image with Gradient Overlay
            SizedBox(
              height: 350.h,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.imageUrl.isEmpty || item.imageUrl.contains('cointelegraph')
                      ? _buildGradientPlaceholder()
                      : Image.network(
                          item.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_,__,___) => _buildGradientPlaceholder(),
                        ),
                  // Gradient Overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.4, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Content Body
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tag
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 1.w),
                    ),
                    child: Text(
                      tag.toUpperCase(),
                      style: GoogleFonts.lato(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w900,
                        fontSize: 12.sp,
                        letterSpacing: 1.0.w,
                      ),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  
                  // Large Bold Title
                  Text(
                    item.title,
                    style: GoogleFonts.playfairDisplay(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 28.sp,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  SizedBox(height: 24.h),
                  
                  // Source + Timestamp Row
                  Row(
                    children: [
                      Text(
                        item.sourceName,
                        style: GoogleFonts.lato(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 14.sp,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        "•",
                        style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        timeAgo(item.timestamp),
                        style: GoogleFonts.lato(
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontSize: 14.sp,
                        ),
                      ),
                      const Spacer(),
                      // Blue Clickable Text: "Original" with Underline
                      GestureDetector(
                        onTap: _openOriginal,
                        child: Text(
                          "Original",
                          style: GoogleFonts.lato(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16.sp,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.blueAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.h),
                    child: Divider(color: Colors.white12, thickness: 1.w),
                  ),
                  
                  // Full Summary
                  Text(
                    item.summary,
                    style: GoogleFonts.lato(
                      color: isDark ? Colors.white70 : Colors.black87,
                      fontSize: 18.sp,
                      height: 1.7,
                    ),
                  ),
                  SizedBox(height: 60.h),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
