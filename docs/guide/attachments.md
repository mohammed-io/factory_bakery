# Attachments

File attachments need the opt-in plugin:

```ruby
require 'factory_bakery/attachments'
```

In Rails, put the require in an initializer or at the top of a definition file. Requiring the file is the switch. The core never registers it on its own. The plugin does nothing when neither attachment library is loaded.

## What it does

For each attachment a valid record **needs** (a presence validator applies, `if:` / `unless:` honored), the plugin attaches a tiny real fixture bundled in the gem. It picks the first fixture the attachment's allowed content types accept:

| Order | Content type | File |
| --- | --- | --- |
| 1 | `image/png` | 1x1 PNG (default) |
| 2 | `image/jpeg` | JPEG |
| 3 | `image/gif` | GIF |
| 4 | `image/webp` | WebP |
| 5 | `video/mp4` | MP4 |
| 6 | `audio/mpeg` | MP3 |
| 7 | `application/pdf` | PDF |
| 8 | `text/plain` | text |

A `type/*` wildcard and a Regexp rule are understood. All fixtures are under 1 KB, so size rules pass. Images are 1x1, which satisfies any dimension rule that admits them. Nothing is fetched from the network and `*_remote_url` setters are never used.

Supported libraries:

| Library | Macro | Notes |
| --- | --- | --- |
| Active Storage | `has_one_attached` | `has_many_attached` is left alone |
| Paperclip / kt-paperclip | `has_attached_file` | `do_not_validate_attachment_file_type` means no rule, so the PNG is used. Paperclip support is tested against a stand-in module, not the real gem |

## Precedence

Attachments follow the normal [precedence](overrides-and-precedence.md). A declaration, a call-site override and `skip` all win. An optional attachment stays empty by default.

```ruby
FactoryBakery.define(User) do
  skip :avatar                                       # leave the attachment alone
  cover_image { fixture_file_upload('cover.png') }   # decide it explicitly
end

FactoryBakery.bake(User)                             # required attachments filled
FactoryBakery.bake(User, fill_optional: true)        # optional ones too
FactoryBakery.bake(User, fill_optional: %i[avatar])  # just this one
```

(`fixture_file_upload` is a Rails test helper. Inside a definition file, build the attachable yourself unless that helper is in scope.)

## Persistence

`bake` stays database-free: building the attachable writes nothing. `bake!` stores the blob and the attachment row inside the same transaction as the rest of the graph, and uploads the file when that transaction commits.

## Without the plugin

Attachment names are removed from the attribute universe. `bake` never assigns a String to `avatar` and never raises, and the attachment stays unattached. A presence-validated attachment will then fail validation: load the plugin.

## Error

If no bundled fixture satisfies the allowed content types:

```
no bundled attachment fixture matches ["application/zip"]; declare the attachment explicitly or allow one of image/png, image/jpeg, image/gif, image/webp, video/mp4, audio/mpeg, application/pdf, text/plain
```

Declare the attachment yourself in that case.

## Remote-URL setters

Names matching `*_remote_url`, `remote_url`, `remote_*url` are treated as side-effecting writers. They are never filled, even with `fill_optional: true`. A `NOT NULL` column with no default gets `''`. Declare a value, or use `skip`, when you need otherwise.
