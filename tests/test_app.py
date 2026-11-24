"""Pytest suite for the ACEest Fitness & Gym Flask application."""
import pytest

import app as app_module
from app import app


@pytest.fixture
def client():
    """Provide a Flask test client and reset the in-memory store per test."""
    app.config["TESTING"] = True
    app_module.workouts.clear()
    app_module._next_id = 1
    with app.test_client() as test_client:
        yield test_client


def test_health_check(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "healthy"}


def test_version_endpoint(client):
    response = client.get("/version")
    assert response.status_code == 200
    data = response.get_json()
    assert data["version"] == app_module.APP_VERSION
    assert data["color"] == app_module.DEPLOY_COLOR


def test_release_headers_present(client):
    response = client.get("/health")
    assert response.headers["X-App-Version"] == app_module.APP_VERSION
    assert response.headers["X-Deploy-Color"] == app_module.DEPLOY_COLOR


def test_index_page_loads(client):
    response = client.get("/")
    assert response.status_code == 200
    assert b"ACEest Fitness" in response.data


def test_add_workout_via_json(client):
    response = client.post(
        "/add_workout",
        json={"workout": "Deadlift", "duration": 45},
    )
    assert response.status_code == 201
    data = response.get_json()
    assert data["workout"]["workout"] == "Deadlift"
    assert data["workout"]["duration"] == 45
    assert data["workout"]["id"] == 1


def test_add_workout_via_form(client):
    response = client.post(
        "/add_workout",
        data={"workout": "Bench Press", "duration": "30"},
    )
    assert response.status_code == 201
    assert response.get_json()["workout"]["workout"] == "Bench Press"


def test_get_workouts_returns_total(client):
    client.post("/add_workout", json={"workout": "Squat", "duration": 20})
    client.post("/add_workout", json={"workout": "Run", "duration": 25})

    response = client.get("/workouts")
    assert response.status_code == 200
    data = response.get_json()
    assert len(data["workouts"]) == 2
    assert data["total_duration"] == 45


def test_get_workouts_empty(client):
    response = client.get("/workouts")
    assert response.status_code == 200
    data = response.get_json()
    assert data["workouts"] == []
    assert data["total_duration"] == 0


def test_delete_workout(client):
    client.post("/add_workout", json={"workout": "Squat", "duration": 20})
    response = client.delete("/workouts/1")
    assert response.status_code == 200
    assert response.get_json()["workout"]["workout"] == "Squat"
    assert client.get("/workouts").get_json()["workouts"] == []


def test_delete_missing_workout(client):
    response = client.delete("/workouts/99")
    assert response.status_code == 404
    assert "error" in response.get_json()


def test_stats_with_data(client):
    client.post("/add_workout", json={"workout": "Squat", "duration": 20})
    client.post("/add_workout", json={"workout": "Run", "duration": 45})
    data = client.get("/stats").get_json()
    assert data == {
        "count": 2,
        "total_duration": 65,
        "average_duration": 32.5,
        "longest_duration": 45,
    }


def test_stats_empty(client):
    data = client.get("/stats").get_json()
    assert data["count"] == 0
    assert data["average_duration"] == 0


def test_add_workout_missing_name(client):
    response = client.post("/add_workout", json={"workout": "", "duration": 30})
    assert response.status_code == 400
    assert "error" in response.get_json()


def test_add_workout_invalid_duration(client):
    response = client.post(
        "/add_workout", json={"workout": "Plank", "duration": "abc"}
    )
    assert response.status_code == 400
    assert "error" in response.get_json()


def test_add_workout_non_positive_duration(client):
    response = client.post(
        "/add_workout", json={"workout": "Plank", "duration": 0}
    )
    assert response.status_code == 400
    assert "error" in response.get_json()
