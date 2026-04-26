from typing import Annotated

from dependency_injector.wiring import Provide, inject
from fastapi import (
    APIRouter,
    Cookie,
    Depends,
    HTTPException,
    Response,
    Security,
    status,
)
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.security import OAuth2PasswordRequestForm
from jose import JWTError, jwt

from groots.domain.commands import LoginUser, RegisterUser
from groots.domain.errors import GrootException
from groots.entrypoints.api.container import Container
from groots.entrypoints.api.routes.schemas.user import (
    RegisterRequest,
    TokenResponse,
)
from groots.service_layer.errors import to_http_exception
from groots.service_layer.messagebus import MessageBus
from groots.entrypoints.api.auth import get_current_oauth_user
from groots.config import settings

router = APIRouter(prefix="/auth", tags=["auth"])

_WEBUI_URL = "https://ipfs-webui.groots.rce-studio.com"
_COOKIE_NAME = "groots_webui_token"
_COOKIE_DOMAIN = ".groots.rce-studio.com"


@router.post("/register", status_code=201)
@inject
async def register(
    _: Annotated[dict, Security(get_current_oauth_user, scopes=[settings.USER_WRITE])],
    body: RegisterRequest,
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    try:
        return await bus.handle(
            RegisterUser(
                username=body.username,
                email=body.email,
                password=body.password,
                role_id=body.role_id,
            )
        )
    except GrootException as e:
        raise to_http_exception(e)


@router.post("/login")
@inject
async def login(
    form: Annotated[OAuth2PasswordRequestForm, Depends()],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> TokenResponse:
    try:
        result = await bus.handle(
            LoginUser(email=form.username, password=form.password)
        )
        return TokenResponse(**result)
    except GrootException as e:
        raise to_http_exception(e)


# ── WebUI auth ────────────────────────────────────────────────────────────────


@router.get("/webui-check", status_code=200)
async def webui_check(
    groots_webui_token: Annotated[str | None, Cookie()] = None,
) -> Response:
    """Called by nginx auth_request. Returns 200 (admin) or 401 (not authed)."""
    if not groots_webui_token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
    try:
        payload = jwt.decode(
            groots_webui_token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
        )
        if not payload.get("sub") or not payload.get("is_admin", False):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
    return Response(status_code=200)


@router.get("/webui-login", response_class=HTMLResponse)
async def webui_login_page(next: str = _WEBUI_URL, error: str = "") -> HTMLResponse:
    """Serves the admin login form for the IPFS WebUI."""
    error_html = f'<p class="error">{error}</p>' if error else ""
    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Groots — WebUI Login</title>
  <style>
    *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #0b3a53;
      font-family: system-ui, sans-serif;
      color: #e2e8f0;
    }}
    .card {{
      background: #0f2132;
      border: 1px solid #1e3a4f;
      border-radius: 12px;
      padding: 2.5rem 2rem;
      width: 100%;
      max-width: 360px;
    }}
    h1 {{ font-size: 1.25rem; margin-bottom: 1.5rem; text-align: center; }}
    label {{ display: block; font-size: 0.8rem; margin-bottom: 0.3rem; color: #94a3b8; }}
    input {{
      width: 100%;
      padding: 0.6rem 0.8rem;
      background: #1a2e3f;
      border: 1px solid #2d4a5e;
      border-radius: 6px;
      color: #e2e8f0;
      font-size: 0.95rem;
      margin-bottom: 1rem;
    }}
    input:focus {{ outline: none; border-color: #3b82f6; }}
    button {{
      width: 100%;
      padding: 0.65rem;
      background: #3b82f6;
      color: #fff;
      border: none;
      border-radius: 6px;
      font-size: 0.95rem;
      cursor: pointer;
    }}
    button:hover {{ background: #2563eb; }}
    .error {{ color: #f87171; font-size: 0.85rem; margin-bottom: 1rem; text-align: center; }}
  </style>
</head>
<body>
  <div class="card">
    <h1>Groots WebUI</h1>
    {error_html}
    <form method="post" action="/api/auth/webui-login?next={next}">
      <label for="username">Email</label>
      <input id="username" name="username" type="email" autocomplete="email" required>
      <label for="password">Password</label>
      <input id="password" name="password" type="password" autocomplete="current-password" required>
      <button type="submit">Sign in</button>
    </form>
  </div>
</body>
</html>"""
    return HTMLResponse(content=html)


@router.post("/webui-login")
@inject
async def webui_login_submit(
    form: Annotated[OAuth2PasswordRequestForm, Depends()],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
    next: str = _WEBUI_URL,
) -> RedirectResponse:
    """Validates credentials, sets an HttpOnly cookie, redirects to the webui."""
    try:
        result = await bus.handle(
            LoginUser(email=form.username, password=form.password)
        )
    except GrootException:
        login_url = f"/api/auth/webui-login?next={next}&error=Invalid+email+or+password"
        return RedirectResponse(url=login_url, status_code=303)

    # Decode to verify admin — only admins may access the IPFS WebUI
    try:
        payload = jwt.decode(
            result["access_token"],
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
        )
    except JWTError:
        login_url = f"/api/auth/webui-login?next={next}&error=Authentication+failed"
        return RedirectResponse(url=login_url, status_code=303)

    if not payload.get("is_admin", False):
        login_url = f"/api/auth/webui-login?next={next}&error=Admin+access+required"
        return RedirectResponse(url=login_url, status_code=303)

    redirect = RedirectResponse(url=next, status_code=303)
    redirect.set_cookie(
        key=_COOKIE_NAME,
        value=result["access_token"],
        httponly=True,
        secure=True,
        samesite="lax",
        domain=_COOKIE_DOMAIN,
        max_age=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )
    return redirect
