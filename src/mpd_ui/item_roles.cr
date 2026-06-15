module MPDUI
  module ItemRoles
    TITLE     = Qt6::ItemDataRole.new(Qt6::ItemDataRole::User.value + 1)
    SUBTITLE  = Qt6::ItemDataRole.new(Qt6::ItemDataRole::User.value + 2)
    ICON_KIND = Qt6::ItemDataRole.new(Qt6::ItemDataRole::User.value + 3)

    PLAYLIST_ROW_TYPE      = Qt6::ItemDataRole.new(Qt6::ItemDataRole::User.value + 10)
    PLAYLIST_NAME          = Qt6::ItemDataRole.new(Qt6::ItemDataRole::User.value + 11)
    PLAYLIST_SONG_POSITION = Qt6::ItemDataRole.new(Qt6::ItemDataRole::User.value + 12)
    PLAYLIST_SONG_URI      = Qt6::ItemDataRole.new(Qt6::ItemDataRole::User.value + 13)

    LYRICS_TIME_MS = Qt6::ItemDataRole.new(Qt6::ItemDataRole::User.value + 20)
  end
end
