(async () => {

	const titles = [];
	const links = [];
	// const sidebar = document.getElementById('headlessui-disclosure-panel-27');
	const sidebar = $0;
	const wait = async ()=>{

		return new Promise((resolve)=>{
			setTimeout(resolve,1e3);
		});
	};

	const elements = sidebar.querySelectorAll('button.items-start');

	for(const element of elements){

		try {

			element.click();

			await wait();


			let link = document.querySelector('video source[src*="/720/"]').src;
			const title = element.querySelector('span').innerText;

			if(! link) {
				link = document.querySelector('video source[src*="vid.faradars"]').src;
			}

			if(! link) {
				link = document.querySelector('video source[src$=".mp4"]').src;
			}

			if(! link) {
				link = document.querySelector('video source[src*=".mp4"]').src;
			}

			links.push(link);
			titles.push(title);

		} catch (errror) {

		}

	}

	console.log(links);
	console.log(titles);
})();
