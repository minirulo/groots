const conn = new Mongo();
db = conn.getDB(process.env.MONGO_DB);
db.createCollection('users', { capped: false });
db['users'].insertMany([
    {
        "username": "user",
        "email": "user@groots.com",
        "hashed_password": "$2b$12$J179NobLgC.54cCuOn9v4uv84kL/jK0gkfXJTxbaGEHxGfVaQqi5a", // "password"
        "role_id": "69d8a9e00551589717627afc",
        "created_at": {
            "$date": "2026-04-10T07:52:29.394Z"
        },
        "is_active": true,
        "is_admin": false,
        "storage_quota_bytes": 10737418240,
        "used_storage_bytes": 0
    },
    {
        "username": "admin",
        "email": "admin@groots.com",
        "hashed_password": "$2b$12$J179NobLgC.54cCuOn9v4uv84kL/jK0gkfXJTxbaGEHxGfVaQqi5a",
        "role_id": "69d8bc540551589717627b01",
        "created_at": {
            "$date": "2026-04-10T07:52:29.394Z"
        },
        "is_active": true,
        "is_admin": false,
        "storage_quota_bytes": 10737418240,
        "used_storage_bytes": 0
    }
]);