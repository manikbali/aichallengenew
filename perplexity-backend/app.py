from flask import Flask, request, jsonify, redirect, url_for
from langchain_openai import ChatOpenAI  # Updated import for chat models
from flask_cors import CORS
from dotenv import load_gotenv
import os

load_dotenv()
openai_api_key=os.getenv("OPENAI_API_KEY") #Save OPENAI_API_KEY as environment before running this code
app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": "*"}})  # Allows CORS for all origins on /api routes

# Initialize ChatOpenAI model (gpt-4) with API key
llm = ChatOpenAI(model="gpt-4")

@app.route("/", methods=["GET"])
def home():
    return '''
        <html>
            <body>
                <h1>Welcome to the API</h1>
                <form id="queryForm">
                    <input type="text" id="queryInput" placeholder="Enter your query"/>
                    <input type="button" value="Submit" onclick="submitQuery()"/>
                </form>
                <p id="response"></p>
                <script>
                    function submitQuery() {
                        const query = document.getElementById('queryInput').value;
                        fetch('/api/query', {
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/json'
                            },
                            body: JSON.stringify({ query: query })
                        })
                        .then(response => response.json())
                        .then(data => {
                            document.getElementById('response').innerText = JSON.stringify(data);
                        })
                        .catch(error => {
                            console.error('Error:', error);
                        });
                    }
                </script>
            </body>
        </html>
    '''

@app.route("/api/query", methods=["POST"])
def query():
    try:
        data = request.get_json()
        question = data.get("query")

        if not question:
            return jsonify({"error": "No query provided"}), 400

        # Prepare chat messages for the LLM
        messages = [{"role": "user", "content": question}]
        
        # Call the chat model using ChatOpenAI
        result = llm(messages=messages)

        # Access the first message content
        response_text = result.content  # Direct access to the content attribute

        return jsonify({"answer": response_text})
    
    except Exception as e:
        if "insufficient_quota" in str(e):
            return jsonify({"error": "Quota exceeded. Please check your plan and billing details."}), 429
        return jsonify({"error": str(e)}), 500

# Health Check Route
@app.route("/health", methods=["GET"])
def health_check():
    return "OK", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
