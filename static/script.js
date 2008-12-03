
$T = createElementFromString;
Deferred.define();

function del (ticket) {
	$.post("/api/remove.json", { ticket : ticket }, function (d) {
		alert(d);
	});
}

$(function () {
	var table    = $("#tasks tbody");
	var template = table.html();
	table.empty();

	var tasks    = {};

	// alert(template);

	next(function main () {
		return $.getJSON("/api/progress.json").next(function (d) {
			console.log(d)

			var removed_tickets = {};
			for (var k in tasks) if (tasks.hasOwnProperty(k)) removed_tickets[k] = true;

			for (var i = 0; i < d.length; i++) {
				var row;
				var data = d[i];
				data.progress = (data.progress * 100).toFixed(2);
				if (tasks.hasOwnProperty(data.ticket)) {
					row = tasks[d[i].ticket];
				} else {
					row = $T(template, { parent: table[0], data: {
						ticket   : data.ticket,
						uri      : data.uri,
						error    : data.error || "",
						message  : data.message || "",
						plugin   : data.plugin,
						progress : data.progress
					} });
					tasks[d[i].ticket] = row;
				}
				$(row.progressbar).width(data.progress + "%");
				$(row.progressnum).html(data.progress + "%");

				delete removed_tickets[data.ticket];
			}

			for (var k in removed_tickets) if (removed_tickets.hasOwnProperty(k)) {
				$(tasks[k].root).remove();
				delete tasks[k];
			}

					// row.root.className = (i % 2 == 0) ? "even" : "odd"; // TODO
			table.find("tr:odd").attr("class", "odd");
			table.find("tr:even").attr("class", "even");

			return wait(2).next(main);
		});
	}).
	error(function (e) {
		console.log(e);
	});
});
