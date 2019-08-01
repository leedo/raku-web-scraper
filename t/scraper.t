#!/usr/bin/env perl6

use v6;

use Test;
use Web::Scraper;
use URI;

my $scraper = scraper {
  process "li.article[data-post-id]", "articles[]", scraper {
    process "h2", "title", "text";
    process "time.date", "date", "text";
    process "p.excerpt", "excerpt", "text";
    process "h2 a", "url", "@href";
  };
};

ok $scraper.rules<articles>, "articles rule exists";
isa-ok $scraper.rules<articles>.value, Web::Scraper, "is a nested scraper";

my %data = $scraper.scrape(URI.new("http://www.arstechnica.com"));

ok %data<articles>.elems > 0, "articles exist";
ok %data<articles>[0]<url>, "url is set";

say %data<articles>[0]<title>;
say %data<articles>[0]<url>;

done-testing;
