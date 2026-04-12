const conn = new Mongo();
db = conn.getDB(process.env.MONGO_DB);
db.createCollection('roles', { capped: false });
db['roles'].insertMany([
    {
        "_id": ObjectId("69d8a9e00551589717627afc"),
        "name": "User",
        "permissions": [
            "user:read",
            "library:read",
            "library:write",
            "album:read",
            "album:write",
            "playlist:read",
            "playlist:write",
            "genre:read"
        ]
    },
    {
        "_id": ObjectId("69d8bc540551589717627b01"),
        "name": "Admin",
        "permissions": [
            "user:read",
            "user:write",
            "library:read",
            "library:write",
            "library:admin",
            "album:read",
            "album:write",
            "playlist:read",
            "playlist:write",
            "genre:read"
        ]
    }
]);