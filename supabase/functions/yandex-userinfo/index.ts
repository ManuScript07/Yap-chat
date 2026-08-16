type YandexUser = {
  id?: string;
  login?: string;
  default_email?: string;
  emails?: string[];
  display_name?: string;
  real_name?: string;
  birthday?: string | null;
  default_avatar_id?: string;
  is_avatar_empty?: boolean;
};

Deno.serve(async (request) => {
  const authorization = request.headers.get('authorization');
  const accessToken = authorization?.replace(/^(Bearer|OAuth)\s+/i, '').trim();

  if (!accessToken) {
    return Response.json({ error: 'missing_access_token' }, { status: 401 });
  }

  const response = await fetch('https://login.yandex.ru/info?format=json', {
    headers: { Authorization: `OAuth ${accessToken}` },
  });

  if (!response.ok) {
    return Response.json(
      { error: 'yandex_userinfo_failed' },
      { status: response.status },
    );
  }

  const user = (await response.json()) as YandexUser;
  if (!user.id) {
    return Response.json({ error: 'missing_user_id' }, { status: 502 });
  }

  const avatarUrl =
    user.is_avatar_empty === false && user.default_avatar_id
      ? `https://avatars.yandex.net/get-yapic/${user.default_avatar_id}/islands-200`
      : null;
  const email = user.default_email ?? user.emails?.[0] ?? null;

  return Response.json({
    sub: user.id,
    id: user.id,
    email,
    email_verified: email !== null,
    name: user.real_name ?? user.display_name ?? user.login ?? null,
    preferred_username: user.login ?? null,
    picture: avatarUrl,
    birthday: user.birthday ?? null,
  });
});
