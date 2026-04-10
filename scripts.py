
import urllib.parse
from pymongo import MongoClient

# 1. Connection Setup
username = "Gurpreet"
password = "gurpreet@16"
escaped_password = urllib.parse.quote_plus(password)
uri = f"mongodb+srv://{username}:{escaped_password}@cluster0.gngaygj.mongodb.net/?appName=Cluster0"

client = MongoClient(uri)
db = client['test'] 

def run_all_tasks():
    print(" Start Computing\n")

    # --- Q1: Weekly Averages & Percentiles ---
    # Logic: Group by user/week, then calculate the average of those counts.
    q1_pipeline = [
        {"$group": {
            "_id": {"user": "$customer_id", "week": {"$week": "$timestamp"}},
            "session_count": {"$sum": 1},
            "durations": {"$push": "$session_duration_sec"}
        }},
        {"$group": {
            "_id": None,
            "avg_sessions_per_user_per_week": {"$avg": "$session_count"},
            "percentiles": {"$percentile": {"input": "$durations", "p": [0.25, 0.5, 0.75], "method": "approximate"}}
        }}
    ]

    # --- Q2: Feature DAU ---
    # Logic: Count unique users per feature per day.
    q2_pipeline = [
        {"$group": {
            "_id": {"feature": "$feature", "day": {"$dateToString": {"format": "%Y-%m-%d", "date": "$timestamp"}}},
            "unique_users": {"$addToSet": "$customer_id"}
        }},
        {"$project": {
            "feature": "$_id.feature", "date": "$_id.day", "DAU": {"$size": "$unique_users"}
        }},
        {"$limit": 5}
    ]

    # --- Q3: Simple Funnel ---
    # Logic: Use $facet to count users at each step independently.
    q3_pipeline = [
        {"$facet": {
            "signup": [{"$match": {"step": "signup"}}, {"$count": "total"}],
            "login": [{"$match": {"step": "first_login"}}, {"$count": "total"}],
            "workspace": [{"$match": {"step": "workspace_created"}}, {"$count": "total"}]
        }}
    ]

    # --- Q4: Engagement Ranking ---
    # Logic: Score = (Sessions) + (Unique Features Used * 2).
    q4_pipeline = [
        {"$group": {
            "_id": "$customer_id",
            "sessions": {"$sum": 1},
            "unique_features": {"$addToSet": "$feature"}
        }},
        {"$project": {
            "engagement_score": {"$add": ["$sessions", {"$multiply": [{"$size": "$unique_features"}, 2]}]}
        }},
        {"$sort": {"engagement_score": -1}},
        {"$limit": 20}
    ]

    # EXECUTION & PRINTING
    print("\n Q1 Results:", list(db.final_activity_logs.aggregate(q1_pipeline)))
    print("\n Q2 DAU Sample:", list(db.final_activity_logs.aggregate(q2_pipeline)))
    print("\n Q3 Funnel Counts:", list(db.final_onboarding_events.aggregate(q3_pipeline)))
    print("\n Q4 Top 20 Users:", list(db.final_activity_logs.aggregate(q4_pipeline)))

if __name__ == "__main__":
    run_all_tasks()