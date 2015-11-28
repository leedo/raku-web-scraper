use v6;

class Web::Scraper { ... }
class Web::Scraper::Rule {
  has $.selector is required;
  has $.value = "text";
  has $.multiple = False;

  multi method extract (@nodes) {
    if !@nodes {
      return $.multiple ?? [] !! Nil;
    }

    return $.multiple
      ?? [@nodes.map: {self.extract($_)}]
      !! self.extract(@nodes[0]);
  }

  multi method extract ($node) {
    given $.value {
      when Web::Scraper {
        return $node.value.extract($node);
      }
      when "text" {
        return $node.textContent;
      }
      when "html" {
        return $node.toString;
      }
      when /^ '@' / {
        return $node.findvalue($.value);
      }
    }
  }
}
