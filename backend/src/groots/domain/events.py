from dataclasses import dataclass


@dataclass
class UserRegistered:
    user_id: str
    email: str


@dataclass
class TrackAdded:
    user_id: str
    track_id: str
    cid: str


@dataclass
class TrackRemoved:
    user_id: str
    track_id: str
    cid: str


@dataclass
class TrackPinned:
    user_id: str
    track_id: str
    cid: str
