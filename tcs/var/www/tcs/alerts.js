////////////////////////////////////////////////////////////////////////

// This file is part of the UNAM telescope control system.

////////////////////////////////////////////////////////////////////////

// Copyright © 2010, 2011, 2012, 2013, 2014, 2017, 2018, 2019 Alan M. Watson <alan@astro.unam.mx>
//
// Permission to use, copy, modify, and distribute this software for any
// purpose with or without fee is hereby granted, provided that the
// above copyright notice and this permission notice appear in all
// copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
// WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
// AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
// DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
// PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
// TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
// PERFORMANCE OF THIS SOFTWARE.

////////////////////////////////////////////////////////////////////////

confirmrequest = true;

function submitrequest(request) {
  if (!confirmrequest || confirm("Do you want to submit this request?\n\n" + request + "\n")) {
    $.ajax({
      type: "get",
      url: "request.cgi",
      data: {
        request: request
      },
      dataType: "text",
      success: function (data, status, request) {
        if (data != "ok\r\n") {
          alert(data);
        }
      },
      error: function (data, status, error) {
        alert("server error: " + status + " (" + error + ").");
      }
    });
  }
  return false;
}

function getidentifier() {
  identifier = $("input[name=\"identifier\"]:checked").val()
  if (identifier == undefined) {
    alert("error: no alert selected.")
  }
  return identifier
}

$(function () {
  confirm("alerts.js loading\n")
  $("form#alert-enable").submit(function () {
    identifier = getidentifier()
    if (identifier !== undefined) {
      return submitrequest("selector enablealert " + identifier);
    }
  });
  $("form#alert-disable").submit(function () {
    identifier = getidentifier()
    if (identifier !== undefinded) {
      return submitrequest("selector disablealert " + identifier);
    }
  });
  $("form#telescope-move").submit(function () {
    return submitrequest("telescope move " + $("input#move-args").val());
  });
});
