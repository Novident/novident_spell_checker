abstract class EditDistance {
  final String name;

  EditDistance({required this.name});
  int calculateDistance(String source, String target);
}
