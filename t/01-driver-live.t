use strict;
use warnings;

use Test::More;
use Net::Ping;
use Data::Dumper;

BEGIN {
   my $p = Net::Ping->new("tcp", 2);
    $p->port_number(4444);
    unless ($p->ping('localhost')) {
        plan skip_all => "Selenium server is not running on localhost:4444";
        exit;
    }
    unless (use_ok( 'Selenium::Remote::Driver')) {
        BAIL_OUT ("Couldn't load Driver");
        exit;
    }
}

# Start our local http server
if ($^O eq 'MSWin32')
{
   system("start \"TEMP_HTTP_SERVER\" /MIN perl t/http-server.pl");
}
else
{
    system("perl t/http-server.pl > /dev/null &");
}

my $driver = new Selenium::Remote::Driver(browser_name => 'firefox');
my $website = 'http://localhost:63636';
my $ret;

CHECK_DRIVER: {
                ok(defined $driver, 'Object loaded fine...');
                ok($driver->isa('Selenium::Remote::Driver'), '...and of right type');
                ok(defined $driver->{'session_id'}, 'Established session on remote server');
                $ret = $driver->get_capabilities;
                is($ret->{'browserName'}, 'firefox', 'Right capabilities');
                my $status = $driver->status;
                ok($status->{build}->{version},"Got status build.version");
                ok($status->{build}->{revision},"Got status build.revision");
                ok($status->{build}->{time},"Got status build.time");
              }

IME: {
    SKIP: {
    eval {$driver->available_engines;};
    if($@) {
      skip "ime not available on this system",3;
    }
    };
}

LOAD_PAGE: {
                $driver->get("$website/index.html");
                pass('Loaded home page');
                $ret = $driver->get_title();
                is($ret, 'Hello WebDriver', 'Got the title');
                $ret = $driver->get_current_url();
                ok($ret =~ m/$website/i, 'Got proper URL');
           }

WINDOW: {
            $ret = $driver->get_current_window_handle();
            ok($ret =~ m/^{.*}$/, 'Proper window handle received');
            $ret = $driver->get_window_handles();
            is(ref $ret, 'ARRAY', 'Received all window handles');
            $ret = $driver->get_page_source();
            ok($ret =~ m/^<html/i, 'Received page source');
            eval {$driver->set_implicit_wait_timeout(20001);};
            ok(!$@,"Set implicit wait timeout");
            eval {$driver->set_implicit_wait_timeout(0);};
            ok(!$@,"Reset implicit wait timeout");
            $ret = $driver->get("$website/frameset.html");
            $ret = $driver->switch_to_frame('second');
        }

COOKIES: {
            $driver->get("$website/cookies.html");
            $ret = $driver->get_all_cookies();
            is(@{$ret}, 2, 'Got 2 cookies');
            $ret = $driver->delete_all_cookies();
            pass('Deleting cookies...');
            $ret = $driver->get_all_cookies();
            is(@{$ret}, 0, 'Deleted all cookies.');
            $ret = $driver->add_cookie('foo', 'bar', '/', 'localhost', 0);
            pass('Adding cookie foo...');
            $ret = $driver->get_all_cookies();
            is(@{$ret}, 1, 'foo cookie added.');
            $ret = $driver->delete_cookie_named('foo');
            pass('Deleting cookie foo...');
            $ret = $driver->get_all_cookies();
            is(@{$ret}, 0, 'foo cookie deleted.');
            $ret = $driver->delete_all_cookies();
         }

MOVE: {
        $driver->get("$website/index.html");
        $driver->get("$website/formPage.html");
        $ret = $driver->go_back();
        pass('Clicked Back...');
        $ret = $driver->get_title();
        is($ret, 'Hello WebDriver', 'Got the right title');
        $ret = $driver->go_forward();
        pass('Clicked Forward...');
        $ret = $driver->get_title();
        is($ret, 'We Leave From Here', 'Got the right title');
        $ret = $driver->refresh();
        pass('Clicked Refresh...');
        $ret = $driver->get_title();
        is($ret, 'We Leave From Here', 'Got the right title');
      }

FIND: {
        my $elem = $driver->find_element("//input[\@id='checky']");
        ok($elem->isa('Selenium::Remote::WebElement'), 'Got WebElement via Xpath');
        $elem = $driver->find_element('checky', 'id');
        ok($elem->isa('Selenium::Remote::WebElement'), 'Got WebElement via Id');
        $elem = $driver->find_element('checky', 'name');
        ok($elem->isa('Selenium::Remote::WebElement'), 'Got WebElement via Name');

        $elem = $driver->find_element('multi', 'id');
        $elem = $driver->find_child_element($elem, "option");
        ok($elem->isa('Selenium::Remote::WebElement'), 'Got child WebElement...');
        $ret = $elem->get_value();
        is($ret, 'Eggs', '...right child WebElement');
        $ret = $driver->find_child_elements($elem, "//option[\@selected='selected']");
        is(@{$ret}, 4, 'Got 4 WebElements');
        my $expected_err = "An element could not be located on the page using the "
         . "given search parameters: "
         . "element_that_doesnt_exist,id"
        # the following needs to always be right before the eval
         . " at " . __FILE__ . " line " . (__LINE__+1);
        eval { $driver->find_element("element_that_doesnt_exist","id"); };
        chomp $@;
        is($@,$expected_err,"find_element croaks properly");
      }

EXECUTE: {
        my $script = q{
          var arg1 = arguments[0];
          var elem = window.document.getElementById(arg1);
          return elem;
        };
        my $elem = $driver->execute_script($script,'checky');
        ok($elem->isa('Selenium::Remote::WebElement'), 'Executed script');
        is($elem->get_attribute('id'),'checky','Execute found proper element');
        $script = q{
          var arg1 = arguments[0];
          var callback = arguments[arguments.length-1];
          var elem = window.document.getElementById(arg1);
          callback(elem);
        };
        my $callback = q{return arguments[0];};
        $elem = $driver->execute_async_script($script,'multi',$callback);
        ok($elem->isa('Selenium::Remote::WebElement'),'Executed async script');
        is($elem->get_attribute('id'),'multi','Async found proper element');
}

ALERT: {
        $driver->get("$website/alerts.html");
        $driver->find_element("alert",'id')->click;
        is($driver->get_alert_text,'cheese','alert text match');
        eval {$driver->dismiss_alert;};
        ok(!$@,"dismissed alert");
        $driver->find_element("prompt",'id')->click;
        is($driver->get_alert_text,'Enter your name','prompt text match');
        $driver->send_keys_to_prompt("Larry Wall");
        eval {$driver->accept_alert;};
        ok(!$@,"accepted prompt");
        is($driver->get_alert_text,'Larry Wall','keys sent to prompt');
        $driver->dismiss_alert;
        $driver->find_element("confirm",'id')->click;
        is($driver->get_alert_text,"Are you sure?",'confirm text match');
        eval {$driver->dismiss_alert;};
        ok(!$@,"dismissed confirm");
        is($driver->get_alert_text,'false',"dismissed confirmed correct");
        $driver->accept_alert;
        $driver->find_element("confirm",'id')->click;
        eval {$driver->accept_alert;};
        ok(!$@,"accepted confirm");
        is($driver->get_alert_text,'true',"accept confirm correct");
        $driver->accept_alert;
}

QUIT: {
        $ret = $driver->quit();
        ok((not defined $driver->{'session_id'}), 'Killed the remote session');
      }

# Kill our HTTP Server
if ($^O eq 'MSWin32')
{
   system("taskkill /FI \"WINDOWTITLE eq TEMP_HTTP_SERVER\"");
}
else
{
    `ps aux | grep http-server\.pl | grep perl | awk '{print \$2}' | xargs kill`;
}

done_testing;

