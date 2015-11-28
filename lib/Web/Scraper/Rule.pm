use v6;

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
    return $.value.extract($node)
      if $.value.isa("Web::Scraper");

    given $.value {
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
