
$T = createElementFromString;
Deferred.define();

$(function () {
	var table    = $("#tasks tbody");
	var template = table.html();
	table.empty();

	var tasks    = {};

	// alert(template);

	next(function main () {
		return $.getJSON("/api/progress.json").next(function (d) {
			console.log(d)

			for (var i = 0; i < d.length; i++) {
				var row;
				var data = d[i];
				data.progress = (data.progress * 100).toFixed(2);
				if (tasks.hasOwnProperty(d[i].ticket)) {
					row = tasks[d[i].ticket];
				} else {
					row = $T(template, { parent: table[0], data: {
						ticket   : data.ticket,
						uri      : data.uri,
						error    : data.error || "",
						progress : data.progress
					} });
					row.root.className = (i % 2 == 0) ? "even" : "odd";
					tasks[d[i].ticket] = row;
				}
				$(row.progressbar).width(data.progress + "%");
				$(row.progressnum).html(data.progress + "%");
			}

			return wait(2).next(main);
		});
	}).
	error(function (e) {
		console.log(e);
	});
});
