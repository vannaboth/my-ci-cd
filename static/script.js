const button = document.getElementById('helloButton');
const result = document.getElementById('result');

button.addEventListener('click', async () => {
  result.textContent = 'Loading...';
  try {
    const res = await fetch('/api/hello');
    const data = await res.json();
    result.textContent = data.message;
  } catch (err) {
    result.textContent = 'Error calling API';
  }
});
