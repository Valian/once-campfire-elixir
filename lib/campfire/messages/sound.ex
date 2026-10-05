defmodule Campfire.Messages.Sound do
  @moduledoc "The built-in `/play {name}` sounds (Rails `app/models/sound.rb`): an image or a text each."

  @sounds %{
    "56k" => {:image, "sounds/56k.webp", 79, 33},
    "bell" => {:text, "🔔"},
    "bezos" => {:text, "😆💭"},
    "bueller" => {:text, "anyone?"},
    "butts" => {:text, "👐 🚬"},
    "clowntown" => {:image, "sounds/clowntown.webp", 210, 150},
    "cottoneyejoe" => {:text, "🎶🙉🎶 "},
    "crickets" => {:text, "hears crickets chirping"},
    "curb" => {:image, "sounds/curb.webp", 150, 101},
    "dadgummit" => {:text, "dad gummit!! 🎣"},
    "dangerzone" => {:image, "sounds/dangerzone.webp", 157, 32},
    "danielsan" => {:text, "🎆 🏆 🎆"},
    "deeper" => {:image, "sounds/top.webp", 188, 80},
    "ballmer" => {:text, "developers!"},
    "donotwant" => {:image, "sounds/donotwant.webp", 150, 150},
    "drama" => {:image, "sounds/drama.webp", 300, 16},
    "flawless" => {:text, "#flawless"},
    "glados" => {:text, "🤖💢"},
    "gogogo" => {:text, "Go, go, go!"},
    "greatjob" => {:image, "sounds/greatjob.webp", 79, 16},
    "greyjoy" => {:text, "😖🎺"},
    "guarantee" => {:text, "guarantees it 👌"},
    "heygirl" => {:text, "✨💁✨"},
    "honk" => {:text, "HONK"},
    "horn" => {:text, "🐶 ✂️ 🐱"},
    "horror" => {:text, "💀 💀 💀 💀 💀 💀 💀"},
    "inconceivable" => {:text, "doesn't think it means what you think it means…"},
    "letitgo" => {:text, "❄️👩❄️⛄️❄️"},
    "live" => {:text, "is DOING IT LIVE"},
    "loggins" => {:image, "sounds/loggins.webp", 200, 151},
    "makeitso" => {:text, "make it so 👉"},
    "noooo" => {:text, "👸💀😒"},
    "nyan" => {:image, "sounds/nyan.webp", 36, 15},
    "ohmy" => {:text, "raises an eyebrow 😏"},
    "ohyeah" => {:text, "isn't playing by the rules"},
    "pushit" => {:image, "sounds/pushit.webp", 104, 15},
    "rimshot" => {:text, "plays a rimshot"},
    "rollout" => {:text, "is rolling out 🚗"},
    "rumble" => {:image, "sounds/rumble.webp", 220, 150},
    "sax" => {:text, "🌇🎷🎶"},
    "secret" => {:text, "found a secret area 🔑"},
    "sexyback" => {:text, "🔞"},
    "story" => {:text, "and now you know…"},
    "tada" => {:text, "plays a fanfare 🎏"},
    "tmyk" => {:text, "✨ ⭐️ The More You Know ✨ ⭐️"},
    "totes" => {:text, "😁👍"},
    "trololo" => {:text, "трололо"},
    "trombone" => {:text, "plays a sad trombone"},
    "unix" => {:text, "knows this 💻"},
    "vuvuzela" => {:text, "======<() ~ ♪ ~♫"},
    "what" => {:image, "sounds/what.webp", 100, 131},
    "whoomp" => {:text, "👏‼️😎"},
    "wups" => {:text, "wups!"},
    "yay" => {:image, "sounds/yay.webp", 103, 50},
    "yeah" => {:image, "sounds/yeah.webp", 104, 15},
    "yodel" => {:text, "📣🗻🙉"}
  }

  @doc "`{:image, asset, width, height}` or `{:text, text}` for a sound name, or `nil`."
  def find(name), do: Map.get(@sounds, name)

  def names, do: @sounds |> Map.keys() |> Enum.sort()

  @doc "The sound a plain-text body plays (`/play name`) as `{name, sound}`, or `nil`."
  def for_text(text) do
    with [_, name] <- Regex.run(~r/\A\/play (\w+)\z/, text),
         sound when sound != nil <- find(name) do
      {name, sound}
    else
      _ -> nil
    end
  end
end
