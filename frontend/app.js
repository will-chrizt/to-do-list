const todoList = document.getElementById('todo-list');
const newTodoInput = document.getElementById('new-todo-input');
const addTodoButton = document.getElementById('add-todo-button');

const API_URL = 'http://localhost:5000/api/todos';

// Fetch and render to-do items
async function fetchTodos() {
    try {
        const response = await fetch(API_URL);
        const todos = await response.json();
        todoList.innerHTML = '';
        todos.forEach(todo => {
            const li = document.createElement('li');
            li.textContent = todo.text;
            const deleteBtn = document.createElement('button');
            deleteBtn.textContent = 'X';
            deleteBtn.onclick = () => deleteTodo(todo.id);
            li.appendChild(deleteBtn);
            todoList.appendChild(li);
        });
    } catch (error) {
        console.error('Failed to fetch todos:', error);
    }
}

// Add a new to-do item
async function addTodo() {
    const text = newTodoInput.value.trim();
    if (text) {
        try {
            await fetch(API_URL, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ text })
            });
            newTodoInput.value = '';
            fetchTodos();
        } catch (error) {
            console.error('Failed to add todo:', error);
        }
    }
}

// Delete a to-do item
async function deleteTodo(id) {
    try {
        await fetch(`${API_URL}/${id}`, {
            method: 'DELETE'
        });
        fetchTodos();
    } catch (error) {
        console.error('Failed to delete todo:', error);
    }
}

// Add event listener to the button
addTodoButton.addEventListener('click', addTodo);

// Initial fetch of todos when the page loads
fetchTodos();