import app


def test_home():
    client = app.app.test_client()
    response = client.get('/')
    assert response.status_code == 200


def test_api_hello():
    client = app.app.test_client()
    response = client.get('/api/hello')
    assert response.status_code == 200
    assert response.get_json() == {'message': 'Hello World!'}
