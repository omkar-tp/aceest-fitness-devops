"""ACEest Fitness & Gym - Flask web application.

A lightweight workout management service exposing both a simple web UI and a
JSON REST API. The application keeps an in-memory list of workouts, which makes
it fully self-contained and ideal for automated CI/CD pipelines (no external
database required).
"""
from __future__ import annotations

import os

from flask import Flask, jsonify, render_template, request

app = Flask(__name__)

# Release metadata injected at build/deploy time (Docker ARG / Kubernetes env).
# DEPLOY_COLOR identifies the track (blue, green, stable, canary, ...), which
# lets deployment strategies be verified from the outside.
APP_VERSION = os.getenv("APP_VERSION", "2.0.1")
DEPLOY_COLOR = os.getenv("DEPLOY_COLOR", "default")


@app.after_request
def add_release_headers(response):
    """Expose which release served the request (used to verify rollouts)."""
    response.headers["X-App-Version"] = APP_VERSION
    response.headers["X-Deploy-Color"] = DEPLOY_COLOR
    return response


# In-memory store. Each workout is a dict: {"id", "workout", "duration"}.
workouts: list[dict] = []
_next_id = 1


def _add_workout(name: str, duration: int) -> dict:
    """Validate input and append a new workout to the store.

    Raises ValueError if the input is invalid.
    """
    global _next_id

    if name is None or str(name).strip() == "":
        raise ValueError("Workout name is required.")

    try:
        duration_int = int(duration)
    except (TypeError, ValueError):
        raise ValueError("Duration must be a whole number of minutes.")

    if duration_int <= 0:
        raise ValueError("Duration must be a positive number of minutes.")

    workout = {
        "id": _next_id,
        "workout": str(name).strip(),
        "duration": duration_int,
    }
    workouts.append(workout)
    _next_id += 1
    return workout


@app.route("/")
def index():
    """Render the home page with the current list of workouts."""
    total = sum(item["duration"] for item in workouts)
    return render_template(
        "index.html",
        workouts=workouts,
        total=total,
        version=APP_VERSION,
        color=DEPLOY_COLOR,
    )


@app.route("/health")
def health():
    """Health-check endpoint used by Docker and CI/CD pipelines."""
    return jsonify({"status": "healthy"}), 200


@app.route("/version")
def version():
    """Report the running release and deployment track."""
    return jsonify({"version": APP_VERSION, "color": DEPLOY_COLOR}), 200


@app.route("/add_workout", methods=["POST"])
def add_workout():
    """Add a workout via form submission or JSON payload."""
    if request.is_json:
        data = request.get_json(silent=True) or {}
        name = data.get("workout")
        duration = data.get("duration")
    else:
        name = request.form.get("workout")
        duration = request.form.get("duration")

    try:
        workout = _add_workout(name, duration)
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    return jsonify({"message": "Workout added successfully.", "workout": workout}), 201


@app.route("/workouts", methods=["GET"])
def get_workouts():
    """Return all recorded workouts and the total duration as JSON."""
    total = sum(item["duration"] for item in workouts)
    return jsonify({"workouts": workouts, "total_duration": total}), 200


@app.route("/workouts/<int:workout_id>", methods=["DELETE"])
def delete_workout(workout_id: int):
    """Remove a workout by id (added in v2.0.0)."""
    for index, item in enumerate(workouts):
        if item["id"] == workout_id:
            removed = workouts.pop(index)
            return jsonify({"message": "Workout deleted.", "workout": removed}), 200
    return jsonify({"error": f"Workout {workout_id} not found."}), 404


@app.route("/stats", methods=["GET"])
def stats():
    """Summarise logged workouts (added in v2.0.0)."""
    durations = [item["duration"] for item in workouts]
    count = len(durations)
    return jsonify(
        {
            "count": count,
            "total_duration": sum(durations),
            "average_duration": round(sum(durations) / count, 2) if count else 0,
            "longest_duration": max(durations) if count else 0,
        }
    ), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
