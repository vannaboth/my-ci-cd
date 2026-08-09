from flask import Flask, render_template, jsonify
import os

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE_DIR = os.path.join(BASE_DIR, 'templates')

app = Flask(__name__, template_folder=TEMPLATE_DIR)

@app.route('/')
def hello():
    return render_template('index.html')   # the HTML page

@app.route('/api/hello')
def api_hello():
    return jsonify(message='Hello World!') # JSON the JS fetches

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 3000))
    app.run(host='0.0.0.0', port=port)