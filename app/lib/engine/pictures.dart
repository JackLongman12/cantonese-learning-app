/// A picture (emoji) for a sentence, card or story line, chosen from keywords in its
/// English meaning, so the Chinese is seen next to an image of what it means. Emoji
/// are drawn by the phone's own font: no image files, nothing to download.
///
/// Order matters: more specific keywords come first ("milk tea" before "tea").
library;

const _pictures = <(String, String)>[
  // drinks and food
  ('milk tea', '🧋'), ('lemon tea', '🍋'), ('yuenyeung', '☕'), ('coffee', '☕'),
  ('tea', '🍵'),
  ('beer', '🍺'),
  ('wine', '🍷'),
  ('juice', '🧃'),
  ('water', '💧'),
  ('egg tart', '🥧'),
  ('pork chop bun', '🍔'),
  ('pineapple bun', '🍞'),
  ('bun', '🥯'),
  ('bread', '🍞'), ('toast', '🍞'), ('congee', '🥣'), ('noodle', '🍜'),
  ('macaroni', '🍝'), ('rice', '🍚'), ('soup', '🍲'), ('dim sum', '🥟'),
  ('dumpling', '🥟'),
  ('har gow', '🥟'),
  ('siu mai', '🥟'),
  ('chicken feet', '🐔'),
  ('chicken', '🍗'), ('goose', '🍗'), ('duck', '🦆'), ('pork', '🥩'),
  ('beef', '🥩'), ('meat', '🥩'), ('fish ball', '🍢'), ('fish', '🐟'),
  ('shrimp', '🦐'), ('prawn', '🦐'), ('crab', '🦀'), ('lobster', '🦞'),
  ('egg', '🥚'), ('vegetable', '🥬'), ('choy sum', '🥬'), ('fruit', '🍎'),
  ('apple', '🍎'), ('orange', '🍊'), ('mango', '🥭'), ('mooncake', '🥮'),
  ('cake', '🍰'), ('dessert', '🍮'), ('sweet', '🍬'), ('ice cream', '🍦'),
  ('spicy', '🌶️'), ('salt', '🧂'), ('breakfast', '🍳'), ('lunch', '🍱'),
  ('dinner', '🍽️'), ('restaurant', '🍽️'), ('menu', '📋'), ('eat', '🍽️'),
  ('hungry', '😋'), ('full', '😋'), ('delicious', '😋'),
  // money and shopping
  ('bill', '🧾'), ('receipt', '🧾'), ('change', '🪙'), ('cash', '💵'),
  ('dollar', '💵'), ('money', '💰'), ('price', '🏷️'), ('discount', '🏷️'),
  ('expensive', '💸'), ('cheap', '🏷️'), ('card', '💳'), ('pay', '💳'),
  ('octopus', '💳'), ('top up', '💳'), ('bank', '🏦'), ('supermarket', '🛒'),
  ('market', '🧺'), ('shop', '🛍️'), ('buy', '🛍️'), ('shirt', '👕'),
  ('clothes', '👕'), ('shoe', '👟'), ('size', '📏'), ('souvenir', '🎁'),
  ('gift', '🎁'), ('red packet', '🧧'),
  // getting around
  ('airport', '✈️'), ('plane', '✈️'), ('flight', '✈️'), ('ferry', '⛴️'),
  ('pier', '⛴️'), ('boat', '⛴️'), ('mtr', '🚇'), ('train', '🚆'),
  ('station', '🚉'), ('tram', '🚋'), ('minibus', '🚐'), ('bus', '🚌'),
  ('taxi', '🚕'), ('driver', '🚕'), ('car', '🚗'), ('parking', '🅿️'),
  ('traffic', '🚦'), ('bridge', '🌉'), ('tunnel', '🚇'), ('border', '🛂'),
  ('passport', '🛂'), ('map', '🗺️'), ('lost', '🗺️'), ('turn left', '⬅️'),
  ('turn right', '➡️'), ('straight', '⬆️'), ('walk', '🚶'), ('road', '🛣️'),
  ('street', '🛣️'), ('exit', '🚪'), ('stairs', '🪜'), ('lift', '🛗'),
  ('escalator', '🛗'), ('toilet', '🚻'), ('queue', '🧍'),
  // weather
  ('typhoon', '🌀'), ('signal', '🌀'), ('rainstorm', '⛈️'), ('thunder', '⛈️'),
  ('rain', '🌧️'), ('umbrella', '☂️'), ('wind', '🌬️'), ('sunny', '☀️'),
  ('hot', '🥵'), ('cold', '🥶'), ('weather', '🌤️'),
  // health
  ('hospital', '🏥'), ('clinic', '🏥'), ('doctor', '🩺'), ('nurse', '🩺'),
  ('medicine', '💊'), ('pill', '💊'), ('fever', '🤒'), ('cough', '😷'),
  ('sick', '🤒'), ('headache', '🤕'), ('hurt', '🤕'), ('pain', '🤕'),
  ('tooth', '🦷'), ('allergic', '🤧'), ('sleep', '😴'), ('tired', '😴'),
  // home
  ('landlord', '🔑'), ('key', '🔑'), ('rent', '🏠'), ('flat', '🏢'),
  ('apartment', '🏢'), ('home', '🏠'), ('house', '🏠'), ('room', '🛏️'),
  ('kitchen', '🍳'), ('cook', '🍳'), ('air conditioner', '❄️'),
  ('electricity', '💡'), ('water bill', '🚰'), ('repair', '🔧'),
  ('broken', '🔧'), ('delivery', '📦'), ('parcel', '📦'), ('courier', '📦'),
  ('neighbour', '🏘️'), ('noise', '🔊'), ('rubbish', '🗑️'),
  // phone and messages
  ('whatsapp', '💬'), ('message', '💬'), ('text', '💬'), ('call', '📞'),
  ('phone', '📱'), ('email', '📧'), ('photo', '📸'), ('picture', '📸'),
  ('wifi', '📶'), ('internet', '🌐'), ('computer', '💻'), ('password', '🔒'),
  // paperwork and work
  ('id card', '🪪'), ('form', '📝'), ('sign', '🪧'), ('notice', '🪧'),
  ('post office', '🏤'), ('letter', '✉️'), ('stamp', '✉️'),
  ('appointment', '📅'), ('meeting', '📅'), ('office', '🏢'), ('boss', '👔'),
  ('manager', '👔'), ('colleague', '🧑‍💼'), ('work', '💼'), ('job', '💼'),
  ('salary', '💰'), ('school', '🏫'), ('class', '🏫'), ('study', '📚'),
  ('exam', '📝'), ('book', '📖'), ('police', '👮'), ('fire', '🔥'),
  ('help', '🆘'), ('emergency', '🆘'),
  // tourism and places
  ('hotel', '🏨'), ('casino', '🎰'), ('church', '⛪'), ('temple', '🛕'),
  ('museum', '🏛️'), ('beach', '🏖️'), ('park', '🌳'), ('ruins', '🏛️'),
  ('tower', '🗼'), ('tourist', '🧳'), ('luggage', '🧳'), ('ticket', '🎫'),
  ('fireworks', '🎆'), ('lantern', '🏮'), ('moon', '🌕'),
  // people and life
  ('wedding', '💒'), ('married', '💍'), ('birthday', '🎂'), ('baby', '👶'),
  ('child', '🧒'), ('kids', '🧒'), ('mum', '👩'), ('mother', '👩'),
  ('dad', '👨'), ('father', '👨'), ('grandma', '👵'), ('grandpa', '👴'),
  ('family', '👨‍👩‍👧'), ('friend', '🧑‍🤝‍🧑'), ('dog', '🐕'), ('cat', '🐱'),
  ('mahjong', '🀄'), ('football', '⚽'), ('game', '🎮'), ('film', '🎬'),
  ('movie', '🎬'), ('song', '🎵'), ('music', '🎵'),
  // time and numbers
  ("o'clock", '🕒'), ('minute', '⏱️'), ('hour', '⏰'), ('time', '⏰'),
  ('late', '⏰'), ('early', '🌅'), ('morning', '🌅'), ('tonight', '🌙'),
  ('night', '🌙'), ('today', '📅'), ('tomorrow', '📅'), ('yesterday', '📅'),
  ('week', '📅'), ('year', '📅'),
  // feelings
  ('thank', '🙏'), ('sorry', '🙏'), ('excuse me', '🙋'), ('angry', '😠'),
  ('happy', '😊'), ('sad', '😢'), ('scared', '😨'), ('love', '❤️'),
  ('crazy', '🤪'), ('idiot', '🤪'), ('fuck', '🤬'), ('damn', '😤'),
];

final _patterns = [
  for (final (k, e) in _pictures)
    (
      RegExp(
        '(^|[^a-z])${RegExp.escape(k)}(s|es)?([^a-z]|\$)',
        caseSensitive: false,
      ),
      e,
    ),
];

/// The picture for an English meaning, or null when nothing fits.
String? pictureForMeaning(String english) {
  for (final (re, emoji) in _patterns) {
    if (re.hasMatch(english)) return emoji;
  }
  return null;
}
