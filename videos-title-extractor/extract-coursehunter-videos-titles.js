textArea = document.createElement('textarea');

document.getElementById('lessons-list').querySelectorAll('li.lessons-item').forEach((element)=>{

  const title = element.querySelector('.lessons-title').innerText;
  const duration = element.querySelector('.lessons-duration').innerText;
  const name = element.querySelector('.lessons-name').innerText;
  

   textArea.value +=  `${title} ${name} - ${duration}`;
   textArea.value += "\n";
}); 

console.log(textArea.value);