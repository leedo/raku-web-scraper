use v6;

class Web::Scraper::Rule {
  has $.selector is required;
  has $.value = "text";
  has $.multiple = False;

  method extract($node) {
    given $.value {
      when "text" {
        return $node.textContent;
      }
      default {
        return $node.findvalue($.value);
      }
    }
  }
}
