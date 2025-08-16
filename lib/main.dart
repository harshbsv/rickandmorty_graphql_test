import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

void main() async {
  // We're using HiveStore for persistence, so we need to initialize Hive.
  await initHiveForFlutter();

  // Define the GraphQL endpoint for the Rick and Morty API.
  final HttpLink httpLink = HttpLink('https://rickandmortyapi.com/graphql');

  // Create a ValueNotifier to hold the GraphQL client.
  final ValueNotifier<GraphQLClient> client = ValueNotifier(
    GraphQLClient(
      link: httpLink,
      // The default store is the InMemoryStore, which does NOT persist to disk.
      cache: GraphQLCache(store: HiveStore()),
    ),
  );

  runApp(
    // GraphQLProvider makes the client available to all descendant widgets.
    GraphQLProvider(client: client, child: const MyApp()),
  );
}

// Main application widget.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GraphQL Pagination',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      home: const CharacterListPage(),
    );
  }
}

// A widget to display a paginated list of characters.
class CharacterListPage extends StatefulWidget {
  const CharacterListPage({super.key});

  @override
  State<CharacterListPage> createState() => _CharacterListPageState();
}

class _CharacterListPageState extends State<CharacterListPage> {
  final ScrollController _scrollController = ScrollController();
  // GraphQL query to fetch characters with a dynamic page variable.
  final String getCharacters = r'''
    query GetCharacters($page: Int!) {
      characters(page: $page, filter: { name: "rick" }) {
        info {
          count
          pages
          next
          prev
        }
        results {
          id
          name
          status
          species
          image
        }
      }
    }
  ''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Rick and Morty Characters',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 5,
        shadowColor: Colors.black,
        backgroundColor: Colors.cyan,
      ),
      body: Query(
        // Set the initial query options. We start with page 1.
        options: QueryOptions(
          document: gql(getCharacters),
          variables: const {'page': 1},
        ),
        builder: (QueryResult result, {VoidCallback? refetch, FetchMore? fetchMore}) {
          // Check for loading state.
          if (result.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // Check for errors.
          if (result.hasException) {
            return Center(child: Text('Error: ${result.exception.toString()}'));
          }

          // Extract data from the result.
          final List? characters = result.data?['characters']?['results'];
          final Map? info = result.data?['characters']?['info'];
          final int? nextPage = info?['next'];

          if (characters == null || characters.isEmpty) {
            return const Center(child: Text('No characters found!'));
          }

          // Build the list view with the fetched characters.
          return ListView.builder(
            controller: _scrollController,
            itemCount:
                characters.length +
                (nextPage != null
                    ? 1
                    : 0), // Add one for the "Load More" button.
            itemBuilder: (context, index) {
              if (index == characters.length) {
                // This is the "Load More" item.
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  child: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        // Check if there is a next page to load.
                        if (nextPage != null) {
                          fetchMore!(
                            FetchMoreOptions(
                              variables: {'page': nextPage},
                              updateQuery: (existing, newResult) {
                                // This is the fix for the MismatchedDataStructureException.
                                // We are now directly modifying the existing data structure
                                // by fetching the lists and merging them. This is a more
                                // reliable pattern.
                                final List<dynamic> oldResults =
                                    existing?['characters']?['results']
                                        as List<dynamic>? ??
                                    [];
                                final List<dynamic> newResults =
                                    newResult?['characters']?['results']
                                        as List<dynamic>? ??
                                    [];
                                final Map<String, dynamic>? newInfo =
                                    newResult?['characters']?['info'];

                                // Clone the existing map to avoid directly mutating the cache.
                                final Map<String, dynamic> updatedQuery =
                                    Map<String, dynamic>.from(existing!);

                                // Update the info object.
                                updatedQuery['characters']['info'] = newInfo;

                                // Combine the lists and update the results array.
                                updatedQuery['characters']['results'] = [
                                  ...oldResults,
                                  ...newResults,
                                ];

                                return updatedQuery;
                              },
                            ),
                          );
                        }
                      },
                      child: const Text('Load More'),
                    ),
                  ),
                );
              }

              // This is a character list item.
              final character = characters[index];
              return Card(
                elevation: 4,
                margin: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(character['image']),
                  ),
                  title: Text(character['name']),
                  subtitle: Text(
                    '${character['species']} - ${character['status']}',
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
