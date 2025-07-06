import 'package:flutter/material.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: TodoList(),
    );
  }
}

class TodoList extends StatefulWidget {
  @override
  _TodoListState createState() => _TodoListState();
}

class _TodoListState extends State<TodoList> {
  final List<String> _todoItems = [];

  void _addTodoItem(String task) {
    setState(() {
      _todoItems.add(task);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('TODOリスト'),
      ),
      body: ListView.builder(
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(_todoItems[index]),
          );
        },
        itemCount: _todoItems.length,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _displayAddTodoDialog(context),
        tooltip: '追加',
        child: Icon(Icons.add),
      ),
    );
  }

  void _displayAddTodoDialog(BuildContext context) async {
    String newTask = '';
    await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('新規'),
          content: TextField(
            onChanged: (String value) {
              newTask = value;
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('取り消し'),
            ),
            TextButton(
              onPressed: () {
                if (newTask.isNotEmpty) {
                  _addTodoItem(newTask);
                }
                Navigator.pop(context);
              },
              child: Text('追加'),
            ),
          ],
        );
      },
    );
  }
}
