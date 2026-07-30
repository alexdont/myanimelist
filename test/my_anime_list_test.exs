defmodule MyAnimeListTest do
  use ExUnit.Case, async: false

  alias MyAnimeList.{Client, Token}

  @cid "test-client-id"

  setup do
    Application.put_env(:myanimelist, :req_options, plug: {Req.Test, MyAnimeList})
    on_exit(fn -> Application.delete_env(:myanimelist, :req_options) end)
    :ok
  end

  describe "media-type dispatch (unit)" do
    test "progress_key / statuses / page_url differ by media" do
      assert MyAnimeList.progress_key(:anime) == "num_episodes_watched"
      assert MyAnimeList.progress_key(:manga) == "num_chapters_read"

      assert "watching" in MyAnimeList.statuses(:anime)
      assert "reading" in MyAnimeList.statuses(:manga)

      assert MyAnimeList.page_url(:anime, 1) == "https://myanimelist.net/anime/1"
      assert MyAnimeList.page_url(:manga, 1) == "https://myanimelist.net/manga/1"
    end

    test "not configured is a value" do
      refute MyAnimeList.configured?("")
      refute MyAnimeList.configured?(nil)
      assert {:error, :not_configured} = MyAnimeList.search(:manga, "blame", "")
    end
  end

  describe "search/4" do
    test "anime hits /v2/anime with the client-id header and normalizes" do
      Req.Test.stub(MyAnimeList, fn conn ->
        assert conn.request_path == "/v2/anime"
        assert Plug.Conn.get_req_header(conn, "x-mal-client-id") == [@cid]

        Req.Test.json(conn, %{
          "data" => [
            %{
              "node" => %{
                "id" => 52991,
                "title" => "Sousou no Frieren",
                "main_picture" => %{"large" => "http://img/l"},
                "mean" => 8.9,
                "media_type" => "tv",
                "start_date" => "2023-09-29"
              }
            }
          ]
        })
      end)

      assert {:ok, [r]} = MyAnimeList.search(:anime, "frieren", @cid)
      assert r.id == 52991
      assert r.title == "Sousou no Frieren"
      assert r.cover_url == "http://img/l"
      assert r.score == 8.9
      assert r.year == 2023
    end

    test "manga hits /v2/manga" do
      Req.Test.stub(MyAnimeList, fn conn ->
        assert conn.request_path == "/v2/manga"
        Req.Test.json(conn, %{"data" => []})
      end)

      assert {:ok, []} = MyAnimeList.search(:manga, "blame", @cid)
    end
  end

  describe "get/4" do
    test "manga details carry chapters/volumes/authors" do
      Req.Test.stub(MyAnimeList, fn conn ->
        assert conn.request_path == "/v2/manga/1"

        Req.Test.json(conn, %{
          "id" => 1,
          "title" => "Blame!",
          "main_picture" => %{"large" => "http://l"},
          "mean" => 8.09,
          "genres" => [%{"name" => "Sci-Fi"}],
          "media_type" => "manga",
          "status" => "finished",
          "num_chapters" => 65,
          "num_volumes" => 10,
          "authors" => [%{"node" => %{"first_name" => "Tsutomu", "last_name" => "Nihei"}}],
          "start_date" => "1997-09-25"
        })
      end)

      assert {:ok, m} = MyAnimeList.get(:manga, 1, @cid)
      assert m.url == "https://myanimelist.net/manga/1"
      assert m.num_chapters == 65
      assert m.num_volumes == 10
      assert m.authors == ["Tsutomu Nihei"]
      assert m.num_episodes == nil
      assert m.studios == []
      assert m.genres == ["Sci-Fi"]
    end

    test "anime details carry episodes/studios" do
      Req.Test.stub(MyAnimeList, fn conn ->
        assert conn.request_path == "/v2/anime/52991"

        Req.Test.json(conn, %{
          "id" => 52991,
          "title" => "Sousou no Frieren",
          "media_type" => "tv",
          "status" => "finished_airing",
          "num_episodes" => 28,
          "studios" => [%{"id" => 11, "name" => "Madhouse"}],
          "start_date" => "2023-09-29"
        })
      end)

      assert {:ok, a} = MyAnimeList.get(:anime, 52991, @cid)
      assert a.url == "https://myanimelist.net/anime/52991"
      assert a.num_episodes == 28
      assert a.studios == ["Madhouse"]
      assert a.num_chapters == nil
      assert a.authors == []
    end

    test "404 becomes :not_found" do
      Req.Test.stub(MyAnimeList, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"error" => "not_found"})
      end)

      assert {:error, :not_found} = MyAnimeList.get(:anime, 999_999, @cid)
    end

    test "transport error is a value" do
      Req.Test.stub(MyAnimeList, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, {:transport, %Req.TransportError{reason: :econnrefused}}} =
               MyAnimeList.search(:manga, "x", @cid)
    end
  end

  describe "list sync" do
    test "my_progress reads the media-correct field" do
      Req.Test.stub(MyAnimeList, fn conn ->
        assert conn.request_path == "/v2/anime/52991"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer tok"]
        Req.Test.json(conn, %{"id" => 52991, "my_list_status" => %{"num_episodes_watched" => 12}})
      end)

      assert {:ok, 12} = MyAnimeList.my_progress(:anime, "tok", 52991)
    end

    test "list_statuses paginates the media list into a map" do
      Req.Test.stub(MyAnimeList, fn conn ->
        assert conn.request_path == "/v2/users/@me/mangalist"

        Req.Test.json(conn, %{
          "data" => [
            %{"node" => %{"id" => 2}, "list_status" => %{"status" => "reading", "score" => 8}}
          ],
          "paging" => %{}
        })
      end)

      assert {:ok, %{2 => %{"status" => "reading", "score" => 8}}} =
               MyAnimeList.list_statuses(:manga, "tok")
    end

    test "update_list_status PATCHes the right path" do
      Req.Test.stub(MyAnimeList, fn conn ->
        assert conn.method == "PATCH"
        assert conn.request_path == "/v2/anime/52991/my_list_status"
        Req.Test.json(conn, %{"status" => "watching", "num_episodes_watched" => 12})
      end)

      assert {:ok, %{"status" => "watching"}} =
               MyAnimeList.update_list_status(:anime, "tok", 52991, %{
                 status: "watching",
                 num_episodes_watched: 12
               })
    end
  end

  describe "oauth" do
    test "authorize_url carries the PKCE + client params" do
      client = %Client{client_id: @cid, client_secret: "s", redirect_uri: "https://ex.com/cb"}
      url = MyAnimeList.authorize_url(client, "state123", "verifier123")

      assert url =~ "response_type=code"
      assert url =~ "client_id=#{@cid}"
      assert url =~ "code_challenge=verifier123"
      assert url =~ "code_challenge_method=plain"
      assert url =~ "state=state123"
    end

    test "oauth_ready? needs both id and secret" do
      assert MyAnimeList.oauth_ready?(%Client{client_id: @cid, client_secret: "s"})
      refute MyAnimeList.oauth_ready?(%Client{client_id: @cid})
    end

    test "exchange_code returns a Token with a future expiry" do
      Req.Test.stub(MyAnimeList, fn conn ->
        assert conn.request_path == "/v1/oauth2/token"

        Req.Test.json(conn, %{
          "access_token" => "at",
          "refresh_token" => "rt",
          "expires_in" => 3600
        })
      end)

      client = %Client{client_id: @cid, client_secret: "s", redirect_uri: "https://ex.com/cb"}

      assert {:ok, %Token{access_token: "at", refresh_token: "rt", expires_at: exp}} =
               MyAnimeList.exchange_code(client, "code", "verifier")

      assert DateTime.compare(exp, DateTime.utc_now()) == :gt
    end

    test "ensure_fresh keeps a valid token and refreshes an expired one" do
      client = %Client{client_id: @cid, client_secret: "s", redirect_uri: "https://ex.com/cb"}

      fresh = %Token{
        access_token: "still-good",
        expires_at: DateTime.add(DateTime.utc_now(), 3600)
      }

      assert {:ok, ^fresh} = MyAnimeList.ensure_fresh(client, fresh)

      Req.Test.stub(MyAnimeList, fn conn ->
        Req.Test.json(conn, %{
          "access_token" => "new",
          "refresh_token" => "rt2",
          "expires_in" => 3600
        })
      end)

      stale = %Token{
        access_token: "old",
        refresh_token: "rt",
        expires_at: DateTime.add(DateTime.utc_now(), -10)
      }

      assert {:ok, %Token{access_token: "new"}} = MyAnimeList.ensure_fresh(client, stale)
    end
  end
end
